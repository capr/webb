
/*
TODO:
	- begin_edit() method
	- save(success_callback) method
	- background save some time after typing
	-

*/

$.fn.seteditable = function(editable_sel) {
	editable_sel = editable_sel || '*[data-editable], [data-fixture]'

	var editor = ContentTools.EditorApp.get()

	if (!editor.isDormant()) {
		editor.syncRegions(editable_sel)
		return
	}
	editor.init(editable_sel)

	editor.addEventListener('saved', function(ev) {

		var regions = ev.detail().regions
		var region_count = Object.keys(regions).length
		if (!region_count)
			return

		var self = this
		self.busy(true)

		var done = function() {
			region_count--;
			if (region_count == 0)
				self.busy(false)
		}

		for (name in regions)
			if (regions.hasOwnProperty(name)) {
				var args = []
				args.push(regions[name])
				args.push(done)
				$('#'+name).trigger('content_saved', args)
			}
	})

	editor.addEventListener('started', function(ev) {
		editor.highlightRegions(true)
		setTimeout(function() {
			editor.highlightRegions(false)
		}, 500)

		// focus on the first region
		var region = editor.orderedRegions()[0]
		if (region) {
			var elem = region.children[0]
			if (elem) {
				elem.focus()
				// move caret to the end of the text
				var range = new ContentSelect.Range(1/0, 1/0)
				var element = elem.domElement()
				range.select(element)
			}
		}
	})

}

