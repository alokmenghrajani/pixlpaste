/**
 * pixlpaste.com: A simple, free & reliable way to share pixels.
 *
 * TODO List:
 *
 * - rewrite browser compatiblity jonx
 *   - make it look nice on iphone?
 *
 * - consider writing the file upload + drag'n' drop in opa instead of
 *   the external js binding jonx
 *
 * - base64 decode the data on the client side before uploading.
 *   => waiting for: opa bug fix
 *
 * - Fix date (hard coded UTC) issue
 *
 * - about page, help page
 *
 * - stats page
 *   - keep track of prefered upload method
 *
 * - like / twitter buttons
 *
 * - drag'n'drop from other sites
 *
 * - clean up css. Improve centering code?
 *
 * - improve urls we generate
 *
 * To compile:
 * - debug:
 * opa-plugin-builder -o pixlpaste_binding pixlpaste_binding.js
 * opa --parser js-like pixlpaste_binding.opp amazon_s3.opa amazon_s3_auth.opa pixlpaste.opa --
 *
 * - release:
 * opa-plugin-builder -o pixlpaste_binding pixlpaste_binding.js
 * opa --parser js-like --compile-release pixlpaste_binding.opp amazon_s3.opa amazon_s3_auth.opa pixlpaste.opa
 * sudo nohup ./pixlpaste.exe -p 80 & disown
 */

import stdlib.web.client
import stdlib.crypto
import stdlib.web.canvas

type pixel = {
  intmap(string) data,
  string secret
}

type upload_info = {
  string id,
  string secret,
  int offset
}

database stringmap(pixel) /pixels

client hook_paste = %%pixlpaste_binding.hook_paste%%
client hook_drop = %%pixlpaste_binding.hook_drop%%
client hook_file_chooser = %%pixlpaste_binding.hook_file_chooser%%
client get_image_size = %%pixlpaste_binding.get_image_size%%

/**
 * These callbacks gets called from the external js.
 *
 * See pixlpaste_binding.js
 */
function void handle_paste(string data) {
  if (data == "") {
    // TODO: log this event!
    render_failure("Sorry, your paste failed. Are you trying to paste an image? Please try again!")
  } else {
    // TODO: waterfall logs
    render_preview(data)
  }
}

function void handle_drop(string data) {
  if (data == "") {
    // TODO: log this event!
    render_failure("Sorry, your drop failed. Are you trying to drop an image? Please try again!")
  } else {
    // TODO: waterfall logs
    render_preview(data)
  }
}

function void handle_file_chooser(string data) {
  if (data == "") {
    // TODO: log this event!
    render_failure("Sorry, your file is invalid. Are you trying to choose an image? Please try again!")
  } else {
    // TODO: waterfall logs
    render_preview(data)
  }
}

function void render_failure(string message) {
  #error = message;
  Dom.remove_class(#error, "hidden")
  Dom.add_class(#help4, "hidden")
  Dom.add_class(#help4_arrow, "hidden")
  Dom.add_class(#label, "hidden")
  Dom.set_property_unsafe(#preview, "src", "http://pixlpaste.s3.amazonaws.com/pixels/preview.png")
}

function void render_preview(string data) {
  Dom.add_class(#error, "hidden");
  Dom.remove_class(#help4, "hidden")
  Dom.remove_class(#help4_arrow, "hidden")
  Dom.set_property_unsafe(#preview, "src", data)

  get_image_size("preview", function(w, h) {
    #label = <>Preview not rendered at original size.<br/>Your pixels will be uploaded as {w} x {h}</>
    Dom.remove_class(#label, "hidden")
  })
}

exposed server function s3_upload_data(string id) {
  p = /pixels[id];

  string data = Map.fold(
    function(_, v, r) {
      String.concat("", [r, v])
    },
    p.data,
    ""
  );

  // data is in the following format:
  // data:image/<png|jpeg|etc.>;base64,<base64 encoded data>
  int offset = Option.get(String.index(";base64,", data))+8
  mimetype = String.sub(5, offset-5-8, data)
  data = String.sub(offset, String.length(data)-offset, data)
  data = Crypto.Base64.decode(data)

  AmazonS3.put("pixlpaste", "pixels/{id}", mimetype, data)
  // TODO: handle errors

  // Delete local data, since S3 now has the data
  // TODO: implement file not found logic against S3
  Db.remove(@/pixels[id]/data)

  void
}

client function void upload_data() {
  Dom.add_class(#label, "hidden")

  string data = Option.get(Dom.get_property(#preview, "src"));

  // For now we must upload the data in base64, due to a bug in the framework
  int length = String.length(data);

  // Chunk size is currently set to 4000
  // TODO: find optimal chunk size
  upload_data_aux(data, length, 4000, {id:"", secret:"", offset:0});
}

@async client function void upload_data_aux(string data, int length, int piece_length, upload_info info) {
  if (info.offset < length) {
    // we still have some data to send
    Dom.remove_class(#progress, "hidden");
    float perc = Int.to_float(info.offset) * 100.0 / Int.to_float(length);
    Dom.set_value(#progress, "{Int.of_float(perc)}");

    // compute the length of this piece
    int next_offset = info.offset + piece_length
    int l = if (next_offset>length) { length - info.offset } else { piece_length; }

    string piece = String.substr(info.offset, l, data);

    upload_info next_info =
      if (info.id == "") {
        upload_first_piece(info, piece);
      } else {
        upload_next_piece(info, piece);
      }
    upload_data_aux(data, length, piece_length, next_info);
  } else {
    // We are done :)
    s3_upload_data(info.id)
    Client.goto("/{info.id}");
  }
}

exposed function upload_info upload_first_piece(upload_info info, string piece) {
  // TODO: what if id is already taken?
  string id = Random.generic_string("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", 6);
  string secret = Random.string(10);
  intmap data = Map.empty;
  data = Map.add(0, piece, data);
  /pixels[id] <- {data: data, secret: secret};
  {id: id, secret: secret, offset: info.offset + String.length(piece)}
}

exposed function upload_info upload_next_piece(upload_info info, string piece) {
  pixel pixel = /pixels[info.id];
  if (pixel.secret == info.secret) {
    // make sure user is allowed to write here
    /pixels[info.id]/data[info.offset] <- piece
  } else {
    Debug.warning("secret mismatch: {info.secret} != {pixel.secret}")
    // TODO: log this event in a better place!
  }
  {id: info.id, secret: info.secret, offset:info.offset + String.length(piece)}
}

function resource display(xhtml body) {
  Resource.full_page_with_doctype(
    "pixlpaste.com: simple, free, reliable way to share your pixels",
    {html5},
    <>
      {body}
      <script id="ga" type="text/javascript" src="http://pixlpaste.s3.amazonaws.com/pixels/ga.js"/>
      <div id="barometer"/>
      <script id="ga" type="text/javascript" src="http://pixlpaste.s3.amazonaws.com/pixels/barometer.js"/>
    </>,
    <>
      <link rel="stylesheet" type="text/css" href="http://localhost/~amenghra/pixlpaste.css"/>
      <link rel="stylesheet" type="text/css" href="http://getbarometer.s3.amazonaws.com/assets/barometer/css/barometer.css"/>
      <meta name="description" content="A service to easily and securely share images, screenshots, pixels, photos, etc."/>
      <meta name="keywords" content="share, upload, save, bin, cloud, paste, drop, pixel, image, photo, screenshot"/>
    </>,
    {success},
    []
  );
}

function resource display_image(string id) {
  string id2 =
    if (Db.exists(@/pixels[id])) {
      id;
    } else {
      "file_not_found";
    };

  xhtml label =
    if (Db.exists(@/pixels[id])) {
      <p>
        share your pixels: <a href="http://www.pixlpaste.com/{id}">http://www.pixlpaste.com/{id}</a> |
        <a href="/download/{id2}">download</a>
      </p>
    } else {
      <p>sorry, your pixels were not found</p>
    };

  display(
    <>
      <div id="one">
        <img src="http://pixlpaste.s3-website-us-east-1.amazonaws.com/pixels/{id2}"/>
        {label}
      </div>
    </>
  );
}

function resource display_local_image(string id) {
  xhtml label =
    if (Db.exists(@/pixels[id])) {
      <p>Share your pixels: <a href="http://www.pixlpaste.com/{id}">http://www.pixlpaste.com/{id}</a></p>
    } else {
      <p>sorry, your pixels were not found</p>
    };

  string id2 =
    if (Db.exists(@/pixels[id])) {
      id;
    } else {
      "file_not_found";
    };

  display(
    <>
      <div id="one">
        <img src="/pixels/{id2}"/>
        {label}
      </div>
    </>
  );
}

function resource display_raw_image(string id, string format) {
  // TODO:
  // * fetch data from s3
  // * give a nice filename
  p = /pixels[id]

  string data = Map.fold(function(k, v, r) { String.concat("", [r, v]) }, p.data, "")

  // data is in the following format:
  // data:image/<png|jpeg|etc.>;base64,<base64 encoded data>
  // for now, we'll only locate ";base64," and ignore the first part
  // we'll tell the browser the image is image/png, even if that's
  // not the case (browsers are smart enough to figure things out)
  int offset = Option.get(String.index(";base64,", data)) + 8
  data = String.sub(offset, String.length(data)-offset, data)
  data = Crypto.Base64.decode(data)
  Resource.raw_response(data, format, {success})
}

function resource display_home() {
  match (HttpRequest.get_user_agent()) {
    case {some: {renderer: {~Gecko} ...}}:
      display_pixlpaste();
    case {some: {renderer: {~Webkit, variant: {~Chrome}} ...}}:
      display_pixlpaste();
    case _:
      display(
      <>
        <h1>Sorry, your browser is currently not supported</h1>
        <p>pixlpaste.com has been tested with the following browsers:</p>
        <ul>
          <li>Firefox 3+</li>
          <li>Chrome</li>
        </ul>
      </>);
  }
}

client function void client_init() {
  hook_paste(handle_paste);
  hook_drop(handle_drop);
  hook_file_chooser(handle_file_chooser);

  // Handle upload-on-enter
  Dom.bind(
    Dom.select_body(),
    {keyup},
    function void (e) {
      match (e) {
        case {key_code:{some:key} ...}:
          if ((key == Dom.Key.RETURN) &&
              (Option.get(Dom.get_property(#preview, "src")) != "http://pixlpaste.s3.amazonaws.com/pixels/preview.png")) {
            upload_data()
          }
          void
        case _ :
          void
      }
    }
  )
  void
}

exposed server function void slog(o) {
  Debug.warning(Debug.dump(o))
  void
}

function resource display_pixlpaste() {
/*
  t = match (HttpRequest.get_user_agent()) {
    case {some: {environment: {Macintosh} ...}}:
      {instruction:"Hit Command-V | Drag'n'Drop | Use the file uploader", hint:"use Shift-Control-Command-4 to capture an area of your screen"};
    case _:
      {instruction:"Hit Ctrl-V | Drag'n'Drop | Use the file uploader", hint:"use Alt-PrtSc to capture the current window"};
  };
*/
  display(
    <>
    <div id="logo"><img src="http://pixlpaste.s3.amazonaws.com/pixels/logo.png"/></div>
    <div id="outer" onready={function(_){client_init()}}>
      <div id="middle">
        <div id="inner">
          <div class="help">
            <div id="help1">paste from clipboard</div>
          </div>
      <div class="help">
        <div id="help2">drag 'n' drop an image</div>
      </div>
      <div class="help">
        <div id="help3">use a <a id="file_chooser">file chooser</a></div>
      </div>
      <div class="help">
        <span id="help4" class="hidden">
          <input id=#btn type="button" class="btn success" onclick={function(_) {upload_data();}} value="upload your pixels"/>
        </span>
      </div>
      <div class="help">
        <span id="help1_arrow"><img src="http://pixlpaste.s3.amazonaws.com/pixels/1.png"/></span>
      </div>
      <div class="help">
        <span id="help2_arrow"><img src="http://pixlpaste.s3.amazonaws.com/pixels/2.png"/></span>
      </div>
      <div class="help">
        <span id="help3_arrow"><img src="http://pixlpaste.s3.amazonaws.com/pixels/3.png"/></span>
      </div>
      <div class="help">
        <span id="help4_arrow" class="hidden"><img src="http://pixlpaste.s3.amazonaws.com/pixels/4.png"/></span>
      </div>
      <div id="outer2"><div id="middle2"><div id="inner2">
        <div class="alert-message error hidden" id=#error/>
        <img id=#preview class="preview" src="http://pixlpaste.s3.amazonaws.com/pixels/preview.png" alt=""/>
        <br/>
        <progress id=#progress value="0" max="100" class="hidden"/>
        <div id=#label class="help-block hidden"/>
      </div></div></div>
    </div></div></div>
    <canvas id="canvas" style="border: 1px solid black"/>
    </>
  );
}

function resource start(Uri.relative uri) {
  /pixels["file_not_found"] <- {data:Map.empty, secret:"must remain a secret"}
  match (uri) {
    case {path:{nil} ...}:
      display_home()
    case {path:{hd:"favicon.ico" ...} ...}:
      @static_resource("resources/favicon.png")
    case {path:{hd:"favicon.gif" ...} ...}:
      @static_resource("resources/favicon.png")
    case {path:{hd:"googlee4b78291cdd3f153.html" ...} ...}:
      Resource.raw_text("google-site-verification: googlee4b78291cdd3f153.html")
    case {path:{hd:"robots.txt" ...} ...}:
      Resource.raw_text("User-agent: *\nAllow: /\n")
    case {path:{hd:"local", ~tl} ...}:
      match (tl) {
        case {~hd ...}:
          display_local_image(hd)
      }
    case {path:{hd:"pixels", ~tl} ...}:
      match (tl) {
        case {~hd ...}:
          display_raw_image(hd, "image/png")
      }
    case {path:{hd:"download", ~tl} ...}:
      match (tl) {
        case {~hd ...}:
          display_raw_image(hd, "application/octet-stream")
      }
    case {path:{~hd ...} ...}:
      display_image(hd)
  }
}



/**
 * Start the server
 */
Server.start(Server.http,
  [
    {resources: @static_include_directory("resources")},
    {dispatch: start}
  ]
)
