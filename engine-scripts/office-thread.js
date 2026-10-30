// The office thread: runs inside the engine's em-pthread worker, after zeta.js (both are passed to the
// engine as Module.uno_scripts). It owns the UNO side of one editing session and talks to the page
// over zetajs.mainPort. It never touches the WASM heap directly.
//
// Messages in:  {id, cmd: 'open'|'save'|'export'|'modified'|'close', ...}
// Messages out: {cmd: 'ready'} once, {cmd: 'reply', id, ok, ...} per request, and
//               {cmd: 'request', what: 'save'|'export-pdf'|'print'} when the user asks the editor's own
//               menus or shortcuts to save, export or print (the page decides what happens).
'use strict';

let zetajs, css, desktop, xModel, xFrame, kind;

// Commands that would leave the single-document session, or save behind the page's back.
const ROUTED = {
	'.uno:Save': 'save',
	'.uno:SaveAs': 'save',
	'.uno:SaveACopy': 'save',
	'.uno:SaveAll': 'save',
	'.uno:ExportToPDF': 'export-pdf',
	'.uno:ExportDirectToPDF': 'export-pdf',
	'.uno:ExportTo': 'export-pdf',
	'.uno:Print': 'print',
	'.uno:PrintDefault': 'print',
	'.uno:PrintPreview': 'print'
};
const BLOCKED = new Set([
	'.uno:Open', '.uno:OpenRemote', '.uno:OpenFromWriter', '.uno:OpenFromCalc', '.uno:AddDirect',
	'.uno:NewDoc', '.uno:CloseDoc', '.uno:CloseWin', '.uno:Quit', '.uno:RecentFileList',
	'.uno:SendMail', '.uno:SendMailDocAsMS', '.uno:SendMailDocAsPDF', '.uno:SendMailDocAsOOo',
	'.uno:EditDoc', '.uno:Signature', '.uno:MacroDialog', '.uno:RunMacro', '.uno:BasicIDEAppear'
]);

function prop(Name, Value) {
	return new css.beans.PropertyValue({ Name, Value });
}

function post(msg) {
	zetajs.mainPort.postMessage(msg);
}

function isWriter(m) {
	return !!m.queryInterface(zetajs.type.interface(css.text.XTextDocument));
}

/** Routes the editor's own Save/Export/Print to the page and swallows the commands that would
    open, close or replace the document. Everything else reaches the normal dispatcher. */
function interceptCommands(frame) {
	let slave = null, master = null;
	const dispatchTo = (url) => zetajs.unoObject([css.frame.XDispatch], {
		dispatch() {
			if (ROUTED[url]) post({ cmd: 'request', what: ROUTED[url] });
		},
		addStatusListener() {},
		removeStatusListener() {}
	});
	const queryDispatch = (url, target, flags) => {
		const name = url.Complete;
		if (ROUTED[name] || BLOCKED.has(name)) return dispatchTo(name);
		return slave ? slave.queryDispatch(url, target, flags) : null;
	};
	const interceptor = zetajs.unoObject([css.frame.XDispatchProviderInterceptor], {
		getSlaveDispatchProvider() { return slave; },
		setSlaveDispatchProvider(p) { slave = p; },
		getMasterDispatchProvider() { return master; },
		setMasterDispatchProvider(p) { master = p; },
		queryDispatch,
		queryDispatches(requests) {
			return requests.map((r) => queryDispatch(r.FeatureURL, r.FrameName, r.SearchFlags));
		}
	});
	frame.registerDispatchProviderInterceptor(interceptor);
}

const FILTERS = {
	writer: { pdf: 'writer_pdf_Export' },
	calc: { pdf: 'calc_pdf_Export' }
};

function handle(msg) {
	const t0 = performance.now();
	switch (msg.cmd) {
		case 'open': {
			if (xModel) {
				try { xModel.close(true); } catch (e) { /* already gone */ }
				xModel = null;
			}
			const args = [prop('ReadOnly', !!msg.readOnly)];
			xModel = desktop.loadComponentFromURL('file://' + msg.path, '_default', 0, args);
			if (!xModel) throw new Error('The document could not be opened.');
			kind = isWriter(xModel) ? 'writer' : 'calc';
			xFrame = xModel.getCurrentController().getFrame();
			// Hide the window chrome the page provides itself (title bar, document close button).
			xFrame.getContainerWindow().FullScreen = true;
			interceptCommands(xFrame);
			xModel.setModified(false);
			return { kind, ms: performance.now() - t0 };
		}
		case 'save': {
			// Always a NEW file in the engine's scratch space; the page reads it and uploads it. The
			// snapshot and clearing the modified flag happen in this one step, on the thread that also
			// handles typing, so an edit made while the page uploads is never marked as saved. The page
			// sets the flag back ('mark-modified') if the upload fails.
			xModel.storeToURL('file://' + msg.out, [prop('FilterName', msg.filter), prop('Overwrite', true)]);
			xModel.setModified(false);
			return { ms: performance.now() - t0 };
		}
		case 'export': {
			xModel.storeToURL('file://' + msg.out, [prop('FilterName', FILTERS[kind].pdf), prop('Overwrite', true)]);
			return { ms: performance.now() - t0 };
		}
		case 'modified':
			return { modified: xModel ? !!xModel.isModified() : false };
		case 'mark-modified':
			if (xModel) xModel.setModified(true);
			return {};
		case 'close':
			if (xModel) {
				try { xModel.close(true); } catch (e) { /* already gone */ }
				xModel = null;
			}
			return {};
		default:
			throw new Error('Unknown command ' + msg.cmd);
	}
}

Module.zetajs.then(function (pZetajs) {
	zetajs = pZetajs;
	css = zetajs.uno.com.sun.star;
	desktop = css.frame.Desktop.create(zetajs.getUnoComponentContext());
	zetajs.mainPort.onmessage = function (e) {
		const msg = e.data || {};
		let out;
		try {
			out = { ok: true, ...handle(msg) };
		} catch (err) {
			let message = String(err && err.message || err);
			try { message = zetajs.catchUnoException(err)?.Message || message; } catch (_) { /* not a UNO exception */ }
			out = { ok: false, error: message };
		}
		post({ cmd: 'reply', id: msg.id, ...out });
	};
	post({ cmd: 'ready' });
});
