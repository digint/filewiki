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

    var buildTable = function(header, ary) {
        var html = '<tr><th colspan="2">' + header + ':</th></tr>';
        if(ary) {
	    for(var i = 0, l = ary.length; i < l; i++) {
                var data = ary[i];
                html += '<tr><td>' + data[0] + '</td><td>' + data[1] + '</td></tr>';
            }
        }
        else {
            html += '<tr><td colspan="2">(not available)</td></tr>';
        }
        return html;
    };
    var buildExifTable = function(exif) {
        var html = '<table class="gallery_exiftable"><tbody>';
	for(var i = 0, l = exif.length; i < l; i++) {
            var data = exif[i];
            html += buildTable(data[0], data[1]);
        }
        html += '</tbody></table>';
        return html;
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

            mapEl: true,
            swisstopoEl: true,
            swisstopoCombined: false,

            // useful for debugging:
            //timeToIdle: 400000,
            //timeToIdleOutside: 100000,

            // NOTE: default (44,auto) produces black bars on desktop, but transparent ones on mobile.
            // This is pretty much required as the captions cannot be hidden on desktop!
            // If you want to disable this:
            //barsSize: { top:0, bottom:0 },
	    barsSize: { top:44, bottom:'auto' },

            closeOnScroll: false, // for info panel (scrollwheel exits gallery, wtf?)
            clickToCloseNonZoomable: false, // close on click if non-zoomable

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
                var html = '<b>' + (item.title || item.pid) + '</b>';
                if(item.date) {
                    html += ' <small style="margin-left:1em;">' + item.date + '</small>';
                }
                if(item.summary) {
                    html += '<div>' + item.summary + '</div>';
                }
                if(item.desc) {
                    html += '<div>' + item.desc + '</div>';
                }
                //if(item.author) {
                //    html += '<footer><small>Photo: ' + item.author + '</small></footer>';
                //}

		captionEl.children[0].innerHTML = html;
		return true;
	    },

	    addInfoHTMLFn: function(item, infoContentEl) {
		infoContentEl.innerHTML = buildExifTable(item.exif);
            },

            //isClickableElement: function(el) {
            //    // TODO test this on mobile, not sure if needed (in order to close on click)
            //    return (el.tagName === 'A') || (el.className === 'pswp__info__content');
            //}
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
	gallery = new PhotoSwipe( pswpElement, PhotoSwipeUI_FileWiki, items, options);

	// see: http://photoswipe.com/documentation/responsive-images.html
	var realViewportWidth,
	    useLargeImages = false,
	    firstResize = true,
	    imageSrcWillChange;

	gallery.listen('beforeResize', function() {
	    var dpiRatio = window.devicePixelRatio ? window.devicePixelRatio : 1;
	    dpiRatio = Math.min(dpiRatio, 2.5);
	    realViewportWidth = gallery.viewportSize.x * dpiRatio;

	    //if(realViewportWidth >= 1200 || (!gallery.likelyTouchDevice && realViewportWidth > 800) ) {
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
            // make sure there is always a title, or addCaptionHTMLFn() will not be called...
            item.title = item.title || item.pid;
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
