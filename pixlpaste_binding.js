/**
 * javascript file to handle pasting of images (i.e. handling ctrl-v actions).
 *
 * The code is tested to work on Firefox & Chrome.
 */

##register get_image_size : string, (int, int -> void) -> void
##args(id, cb)
{
  var t = new Image();
  t.onload = function() {
    cb(t.width, t.height);
  }
  t.src = document.getElementById(id).src;
}

##register hook_paste : (string -> void) -> void
##args(cb)
{
  // get the content of a file and pass it to cb
  var file_to_img = function(file) {
    var reader = new FileReader();
    reader.onload = function(e) {
      cb(e.target.result);
    }
    reader.readAsDataURL(file);
  }

  if (navigator.userAgent.indexOf('Firefox') != -1) {
    // special hack for Firefox
    var e = document.createElement('div');
    e.id = 'editor';
    e.contentEditable = true;
    e.style.position = 'fixed';
    e.style.left = '-10000px';
    e.style.top = '0px';
    document.body.appendChild(e);
    setInterval('document.getElementById("editor").focus()', 1);

    document.body.addEventListener("paste", function(e) {
      // need to postpone data processing, using setTimeout(..., 1);
      setTimeout(function() {
        var e = document.getElementById('editor');
        var data = '';
        for (var i=0; i<e.children.length; i++) {
          var node = e.children[i];
          if (node.nodeName == 'img') {
            data = node.src;
            break;
          }
        }
        e.innerHTML = '';
        cb(data);
      }, 1);
    });
  } else {
    // http://dev.w3.org/2006/webapi/clipops/ compliant browsers
    document.body.addEventListener("paste", function(e) {
      for (var t in e.clipboardData.types) {
        var type = e.clipboardData.types[t];
        if (type == 'image/png') {
          var file = e.clipboardData.items[t].getAsFile();
          file_to_img(file);
          return;
        }
      }
      cb('');
    });
  }
}

##register hook_drop : (string -> void) -> void
##args(cb)
{
  // get the content of a file and pass it to cb
  var file_to_img = function(file) {
    var reader = new FileReader();
    reader.onload = function(e) {
      cb(e.target.result);
    }
    reader.readAsDataURL(file);
  }

  var noop_handler = function(e) {
    e.stopPropagation();
    e.preventDefault();
  };
  document.addEventListener("dragenter", noop_handler, false);
  document.addEventListener("dragexit", noop_handler, false);
  document.addEventListener("dragover", noop_handler, false);
  document.addEventListener("drop", function(e) {
    e.preventDefault();
    for (var t in e.dataTransfer.files) {
      var file = e.dataTransfer.files[t];
      var type = file.type;
      if (type && (type.substr(0, 5) == 'image')) {
        file_to_img(file);
        return;
      }
    }
    cb('');
  }, false);
}

##register hook_file_chooser : (string -> void) -> void
##args(cb)
{
  // get the content of a file and pass it to cb
  var file_to_img = function(file) {
    var reader = new FileReader();
    reader.onload = function(e) {
      cb(e.target.result);
    }
    reader.readAsDataURL(file);
  }

  var el = document.createElement('input');
  el.type = 'file';
  el.id='file';
  el.accept="image/*";
  el.className='invisible';
  el.onchange = function(){
    for (var t in el.files) {
      var file = el.files[t];
      var type = file.type;
      if (type && (type.substr(0, 5) == 'image')) {
        file_to_img(file);
        return;
      }
    }
    cb('');
  }
  document.body.appendChild(el);
  document.getElementById('file_chooser').addEventListener(
    "click",
    function(e) {
      el.click();
      return false;
    },
    false
  );
}
