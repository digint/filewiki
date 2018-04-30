(function() {

// based on: http://photoswipe.com/documentation/getting-started.html

var initPhotoSwipe = function() {

    // find nearest parent element
    var closest = function closest(el, fn) {
	return el && ( fn(el) ? el : closest(el.parentNode, fn) );
    };

    var findItemIndex = function(fwuri) {
        if(!fwuri) {
            return;
        }
	for (var i = 0, l = gallery_media.length; i < l; i++) {
            if(gallery_media[i].fwuri === fwuri) {
                return i;
	    }
	}
    };

    var findItem = function(fwuri) {
        return gallery_media[findItemIndex(fwuri)];
    };

    var onThumbnailsClick = function(e) {
	e = e || window.event;
	e.preventDefault ? e.preventDefault() : e.returnValue = false;

	var eTarget = e.target || e.srcElement;

	var clickedListItem = closest(eTarget, function(el) {
            return el.tagName === 'A';
	});
	if(!clickedListItem) {
	    return;
	}

        var linkSrc = clickedListItem.getAttribute('href');

        var itemIndex = findItemIndex(clickedListItem.getAttribute('href'));

        if(itemIndex === undefined) {
            return;
        }

        openPhotoSwipe( itemIndex, document );

	return false;
    };

    var photoswipeParseHash = function() {
	var hash = window.location.hash.substring(1),
	    params = {};

	if(hash.length < 5) { // pid=1
	    return params;
	}

	var vars = hash.split('&');
	for (var i = 0; i < vars.length; i++) {
	    if(!vars[i]) {
		continue;
	    }
	    var pair = vars[i].split('=');
	    if(pair.length < 2) {
		continue;
	    }
	    params[pair[0]] = pair[1];
	}

	if(params.gid) {
	    params.gid = parseInt(params.gid, 10);
	}

	return params;
    };

    var openPhotoSwipe = function(index, galleryElement, disableAnimation, fromURL) {
	var pswpElement = document.querySelectorAll('.pswp')[0],
	    gallery,
	    options,
	    items = gallery_media;

	// define options (if needed)
	options = {
            galleryUID: 1,  // hardcoded, we only have a single gallery per page (TODO hack this away)

            galleryPIDs: true,

            shareButtons: [
                //    {id:'facebook', label:'Share on Facebook', url:'https://www.facebook.com/sharer/sharer.php?u={{url}}'},
                //    {id:'twitter', label:'Tweet', url:'https://twitter.com/intent/tweet?text={{text}}&url={{url}}'},
                //    {id:'pinterest', label:'Pin it', url:'http://www.pinterest.com/pin/create/button/?url={{url}}&media={{image_url}}&description={{text}}'},
                {id:'download', label:'Download image', url:'{{raw_image_url}}', download:true}
            ],

	    getThumbBoundsFn: function(index) {
		// See Options->getThumbBoundsFn section of docs for more info
		var thumbnail = items[index].el,
		    pageYScroll = window.pageYOffset || document.documentElement.scrollTop,
		    rect = thumbnail.getBoundingClientRect();

		return {x:rect.left, y:rect.top + pageYScroll, w:rect.width};
	    },

	    addCaptionHTMLFn: function(item, captionEl, isFake) {
		if(!item.title) {
		    captionEl.children[0].innerText = '';
		    return false;
		}
		captionEl.children[0].innerHTML = item.title +  '<br/><small>Photo: ' + item.author + '</small>';
		return true;
                // axel: add something like this:
                //var captionElement = el.parentNode.getElementsByClassName('gallery_mosaic_caption');
                //if(captionElement.length > 0) {
                //  item.title = captionElement[0].innerHTML;
                //}
	    }

	};


	if(fromURL) {
	    if(options.galleryPIDs) {
		// parse real index when custom PIDs are used
		// http://photoswipe.com/documentation/faq.html#custom-pid-in-url
		for(var j = 0; j < items.length; j++) {
		    if(items[j].pid == index) {
			options.index = j;
			break;
		    }
		}
	    } else {
		options.index = parseInt(index, 10) - 1;
	    }
	} else {
	    options.index = parseInt(index, 10);
	}

	// exit if index not found
	if( isNaN(options.index) ) {
	    return;
	}

	if(disableAnimation) {
	    options.showAnimationDuration = 0;
	}

	// Pass data to PhotoSwipe and initialize it
	gallery = new PhotoSwipe( pswpElement, PhotoSwipeUI_Default, items, options);

	// see: http://photoswipe.com/documentation/responsive-images.html
	var realViewportWidth,
	    useLargeImages = false,
	    firstResize = true,
	    imageSrcWillChange;

	gallery.listen('beforeResize', function() {

	    var dpiRatio = window.devicePixelRatio ? window.devicePixelRatio : 1;
	    dpiRatio = Math.min(dpiRatio, 2.5);
	    realViewportWidth = gallery.viewportSize.x * dpiRatio;


//	    if(realViewportWidth >= 1200 || (!gallery.likelyTouchDevice && realViewportWidth > 800) ) {
            if(realViewportWidth >= 1200 || (!gallery.likelyTouchDevice && realViewportWidth > 800) || screen.width > 1200 ) {
		if(!useLargeImages) {
		    useLargeImages = true;
		    imageSrcWillChange = true;
		}

	    } else {
		if(useLargeImages) {
		    useLargeImages = false;
		    imageSrcWillChange = true;
		}
	    }

	    if(imageSrcWillChange && !firstResize) {
		gallery.invalidateCurrItems();
	    }

	    if(firstResize) {
		firstResize = false;
	    }

	    imageSrcWillChange = false;

	});

	gallery.listen('gettingData', function(index, item) {
	    if( useLargeImages ) {
		item.src = item.o.src;
		item.w = item.o.w;
		item.h = item.o.h;
	    } else {
		item.src = item.m.src;
		item.w = item.m.w;
		item.h = item.m.h;
	    }
	});

	gallery.init();
    };

    // select all gallery elements
    var galleryElements = document.querySelectorAll('div.gallery_mosaic_file a');
    for(var i = 0, l = galleryElements.length; i < l; i++) {
        var el = galleryElements[i];
	el.onclick = onThumbnailsClick;

        // add link to element, used by getThumbBoundsFn()
        var item = findItem(el.getAttribute('href'));
        if(item) {
            item.el = el;
        } else {
            console.error("missing gallery item=" + el.getAttribute('href'));
        }
    }

    // Parse URL and open gallery if it contains #&pid=3&gid=1
    var hashData = photoswipeParseHash();
    if(hashData.pid && hashData.gid) {
	openPhotoSwipe( hashData.pid, document, true, true );
    }
};

initPhotoSwipe();

})();
