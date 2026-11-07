import Foundation

/// What a web app starts from. Small models write web pages with Bootstrap's class names, because
/// they've seen millions of them, and then link Bootstrap from the internet, which isn't there in
/// Preview. So a new app gets a style sheet of its own that answers to those same names, with a
/// cleaner look, and works offline. The model writes what it already knows, and it looks finished.
enum DevKit {
    static let cssName = "kit.css"
    /// The first line of the kit, which says the file is ours to replace.
    static let marker = "/* kit.css: Bootstrap-style classes that work offline, written by Prometheus."

    /// The classes a model is told about. It knows the rest of Bootstrap's names, and most of them work.
    static let vocabulary = """
    container, row, col, col-md-6, g-3, card, card-body, card-title, card-header, btn btn-primary, btn-outline-secondary, \
    btn-sm, btn-close, form-control, form-select, form-label, form-check, form-check-input, form-switch, input-group, \
    list-group, list-group-item, badge text-bg-success, table table-hover, alert alert-info, navbar, navbar-brand, \
    nav nav-pills, nav-link active, progress, progress-bar, modal, modal-dialog, modal-content, d-flex, d-grid, gap-2, \
    justify-content-between, align-items-center, flex-grow-1, mb-3, py-4, text-muted, text-center, fw-semibold, small, \
    shadow-sm, rounded-3, w-100, d-none
    """

    /// The page around the model's markup. Code writes the head, so the links between the files are
    /// always right, and nothing in it reaches for the internet.
    static func shell(title: String, body: String, styles: String, script: String, kit: String = cssName) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escaped(title))</title>
        <link rel="stylesheet" href="\(kit)">
        <link rel="stylesheet" href="\(styles)">
        <script src="\(script)" defer></script>
        </head>
        <body>
        \(body.trimmingCharacters(in: .whitespacesAndNewlines))
        </body>
        </html>

        """
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static let stylesStarter = "/* This app's own styles. kit.css comes first and has the Bootstrap-style classes. */\n"

    /// The shape app.js keeps: all data in one place, one function that draws the page from it, and
    /// events that change the data and draw again. A small model that starts from this rarely loses track
    /// of what's on screen, which is where its own designs go wrong.
    static func scriptSkeleton(storageKey: String) -> String {
        """
        // What the page does. Keep this shape: all data lives in state, render() draws the page from
        // state, and every event changes state, then calls save() and render().
        const $ = (selector) => document.querySelector(selector);
        const $$ = (selector) => [...document.querySelectorAll(selector)];
        const STORAGE_KEY = "\(storageKey)";

        // Everything the app knows.
        let state = load({
          // starting values
        });

        function load(fallback) {
          try {
            return Object.assign(fallback, JSON.parse(localStorage.getItem(STORAGE_KEY)) || {});
          } catch (error) {
            return fallback;
          }
        }

        function save() {
          try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); } catch (error) {}
        }

        // Makes text safe to put inside innerHTML.
        function escapeHtml(text) {
          return String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
        }

        function render() {
          // draw the page from state
        }

        // Events: change state, then save() and render().

        render();

        """
    }

    /// Shown to the model once, as the look to aim for. It's a different app on purpose.
    static let example = """
    <nav class="navbar bg-white border-bottom px-4">
      <span class="navbar-brand">📚 Reading List</span>
      <span class="badge text-bg-primary" id="book-count">0 books</span>
    </nav>
    <main class="container py-4">
      <div class="row g-4">
        <div class="col-md-4">
          <div class="card">
            <div class="card-body">
              <h2 class="h5 card-title">Add a book</h2>
              <form id="book-form">
                <label class="form-label" for="book-title">Title</label>
                <input class="form-control mb-3" id="book-title" placeholder="Book title">
                <button class="btn btn-primary w-100" id="add-book" type="submit">Add</button>
              </form>
            </div>
          </div>
        </div>
        <div class="col-md-8">
          <ul class="list-group" id="book-list"></ul>
          <p class="text-muted text-center py-4" id="empty-note">No books yet.</p>
        </div>
      </div>
    </main>
    """

    // MARK: - The style sheet

    static var css: String { base + utilities }

    private static let colors: [(name: String, hex: String, rgb: String, deep: String, darkText: Bool)] = [
        ("primary", "#4f46e5", "79,70,229", "#3730a3", false),
        ("secondary", "#64748b", "100,116,139", "#334155", false),
        ("success", "#16a34a", "22,163,74", "#166534", false),
        ("danger", "#dc2626", "220,38,38", "#991b1b", false),
        ("warning", "#f59e0b", "245,158,11", "#92400e", true),
        ("info", "#0891b2", "8,145,178", "#155e75", false),
        ("light", "#f1f5f9", "241,245,249", "#334155", true),
        ("dark", "#0f172a", "15,23,42", "#0f172a", false),
    ]

    private static let spaces: [(String, String)] = [("0", "0"), ("1", ".25rem"), ("2", ".5rem"), ("3", "1rem"), ("4", "1.5rem"), ("5", "3rem")]
    private static let breakpoints: [(String, Int)] = [("sm", 576), ("md", 768), ("lg", 992), ("xl", 1200), ("xxl", 1400)]

    private static var base: String {
        var rules = [marker + " Put your own styles in styles.css. */"]
        var root = ":root{"
        for color in colors {
            root += "--bs-\(color.name):\(color.hex);--bs-\(color.name)-rgb:\(color.rgb);--bs-\(color.name)-text-emphasis:\(color.deep);"
        }
        root += "--bs-white:#fff;--bs-black:#000;--bs-surface:#fff;--bs-body-bg:#f6f7fb;--bs-body-color:#1e293b;--bs-emphasis-color:#0f172a;"
        root += "--bs-secondary-color:#64748b;--bs-tertiary-color:#94a3b8;--bs-secondary-bg:#eef1f6;--bs-tertiary-bg:#f8fafc;--bs-border-color:#e2e8f0;"
        root += "--bs-border-radius:.625rem;--bs-border-radius-sm:.45rem;--bs-border-radius-lg:.875rem;--bs-border-radius-xl:1.25rem;--bs-border-radius-pill:50rem;"
        root += "--bs-link-color:var(--bs-primary);--bs-font-sans-serif:system-ui,-apple-system,\"Segoe UI\",Roboto,\"Helvetica Neue\",Arial,sans-serif;"
        root += "--bs-font-monospace:ui-monospace,SFMono-Regular,Menlo,monospace;--bs-focus-ring:0 0 0 .25rem rgba(var(--bs-primary-rgb),.25);"
        root += "--bs-shadow-sm:0 1px 2px rgba(15,23,42,.05),0 1px 3px rgba(15,23,42,.07);--bs-shadow:0 4px 14px rgba(15,23,42,.08),0 1px 3px rgba(15,23,42,.06);"
        root += "--bs-shadow-lg:0 18px 44px rgba(15,23,42,.16);color-scheme:light}"
        rules.append(root)
        // Dark mode, however a model asks for it.
        rules.append("html.dark,body.dark,html.dark-mode,body.dark-mode,html.theme-dark,body.theme-dark,[data-bs-theme=dark],[data-theme=dark]{--bs-surface:#111827;--bs-body-bg:#0b1020;--bs-body-color:#e2e8f0;--bs-emphasis-color:#f8fafc;--bs-secondary-color:#94a3b8;--bs-tertiary-color:#64748b;--bs-secondary-bg:#1e293b;--bs-tertiary-bg:#151c2c;--bs-border-color:#263247;--bs-light:#1e293b;--bs-light-rgb:30,41,59;color-scheme:dark}")
        rules.append(contentsOf: [
            "*,*::before,*::after{box-sizing:border-box}",
            "body{margin:0;font-family:var(--bs-font-sans-serif);font-size:1rem;line-height:1.55;color:var(--bs-body-color);background-color:var(--bs-body-bg);-webkit-font-smoothing:antialiased;transition:background-color .2s,color .2s}",
            "h1,h2,h3,h4,h5,h6,.h1,.h2,.h3,.h4,.h5,.h6{margin:0 0 .5rem;font-weight:650;line-height:1.2;letter-spacing:-.01em;color:var(--bs-emphasis-color)}",
            "h1,.h1{font-size:2.1rem}h2,.h2{font-size:1.7rem}h3,.h3{font-size:1.4rem}h4,.h4{font-size:1.2rem}h5,.h5{font-size:1.05rem}h6,.h6{font-size:.95rem}",
            "p{margin:0 0 1rem}ul,ol{margin:0 0 1rem;padding-left:1.5rem}dl{margin:0 0 1rem}dt{font-weight:650}dd{margin:0 0 .5rem}",
            "a{color:var(--bs-link-color);text-decoration:none}a:hover{text-decoration:underline}",
            "img,svg{max-width:100%;vertical-align:middle}hr{border:0;border-top:1px solid var(--bs-border-color);margin:1rem 0;opacity:1}",
            "small,.small{font-size:.875em}mark,.mark{padding:.1em .25em;background:#fef08a;border-radius:.2rem}",
            "code,kbd,pre{font-family:var(--bs-font-monospace);font-size:.875em}code{color:#be185d}pre{display:block;margin:0 0 1rem;overflow:auto;padding:1rem;background:var(--bs-tertiary-bg);border:1px solid var(--bs-border-color);border-radius:var(--bs-border-radius)}",
            "kbd{padding:.15rem .4rem;color:#fff;background:#1e293b;border-radius:.3rem}",
            "button,input,select,textarea{font:inherit;color:inherit;margin:0}button{cursor:pointer}label{display:inline-block}table{border-collapse:collapse}",
            "blockquote,.blockquote{margin:0 0 1rem;padding-left:1rem;border-left:3px solid var(--bs-border-color);color:var(--bs-secondary-color)}",
            ".lead{font-size:1.2rem;font-weight:400;color:var(--bs-secondary-color)}",
            ".display-1{font-size:4.5rem}.display-2{font-size:4rem}.display-3{font-size:3.5rem}.display-4{font-size:3rem}.display-5{font-size:2.6rem}.display-6{font-size:2.2rem}",
            ".display-1,.display-2,.display-3,.display-4,.display-5,.display-6{font-weight:750;line-height:1.1;letter-spacing:-.02em}",
            ".container,.container-fluid,.container-sm,.container-md,.container-lg,.container-xl,.container-xxl{width:100%;padding-right:1rem;padding-left:1rem;margin-right:auto;margin-left:auto}",
            "@media (min-width:576px){.container,.container-sm{max-width:540px}}@media (min-width:768px){.container,.container-sm,.container-md{max-width:720px}}",
            "@media (min-width:992px){.container,.container-sm,.container-md,.container-lg{max-width:960px}}@media (min-width:1200px){.container,.container-sm,.container-md,.container-lg,.container-xl{max-width:1140px}}",
            "@media (min-width:1400px){.container,.container-sm,.container-md,.container-lg,.container-xl,.container-xxl{max-width:1320px}}",
            ".row{--bs-gutter-x:1.5rem;--bs-gutter-y:0;display:flex;flex-wrap:wrap;margin-top:calc(-1 * var(--bs-gutter-y));margin-right:calc(-.5 * var(--bs-gutter-x));margin-left:calc(-.5 * var(--bs-gutter-x))}",
            ".row>*{flex-shrink:0;width:100%;max-width:100%;padding-right:calc(var(--bs-gutter-x) * .5);padding-left:calc(var(--bs-gutter-x) * .5);margin-top:var(--bs-gutter-y)}",
            ".hstack{display:flex;flex-direction:row;align-items:center;align-self:stretch}.vstack{display:flex;flex:1 1 auto;flex-direction:column;align-self:stretch}",
            // Navigation
            ".navbar{position:relative;display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:.5rem 1rem;padding:.75rem 1rem}",
            ".navbar>.container,.navbar>.container-fluid{display:flex;flex-wrap:inherit;align-items:center;justify-content:space-between;gap:inherit}",
            ".navbar-brand{display:inline-flex;align-items:center;gap:.5rem;font-size:1.15rem;font-weight:700;letter-spacing:-.01em;color:var(--bs-emphasis-color);text-decoration:none;white-space:nowrap}.navbar-brand:hover{text-decoration:none}",
            ".navbar-nav{display:flex;flex-direction:row;flex-wrap:wrap;align-items:center;gap:.25rem;padding:0;margin:0;list-style:none}",
            // There's no Bootstrap script to open a collapsed menu, so it never collapses.
            ".navbar-collapse{display:flex!important;flex-grow:1;flex-wrap:wrap;align-items:center;gap:.5rem 1rem}.navbar-toggler{display:none!important}.navbar-text{color:var(--bs-secondary-color)}",
            ".navbar-dark,.navbar[data-bs-theme=dark],.navbar.bg-dark,.navbar.bg-primary{color:#fff}",
            ".navbar-dark .navbar-brand,.navbar[data-bs-theme=dark] .navbar-brand,.navbar.bg-dark .navbar-brand,.navbar.bg-primary .navbar-brand{color:#fff}",
            ".navbar-dark .nav-link,.navbar[data-bs-theme=dark] .nav-link,.navbar.bg-dark .nav-link,.navbar.bg-primary .nav-link,.navbar-dark .navbar-text,.navbar.bg-dark .navbar-text,.navbar.bg-primary .navbar-text{color:rgba(255,255,255,.78)}",
            ".navbar-dark .nav-link:hover,.navbar-dark .nav-link.active,.navbar.bg-dark .nav-link:hover,.navbar.bg-dark .nav-link.active,.navbar.bg-primary .nav-link:hover,.navbar.bg-primary .nav-link.active{color:#fff;background:rgba(255,255,255,.12)}",
            ".nav{display:flex;flex-wrap:wrap;gap:.25rem;padding:0;margin:0;list-style:none}.nav-item{list-style:none}",
            ".nav-link{display:block;padding:.45rem .85rem;color:var(--bs-secondary-color);font-weight:550;text-decoration:none;background:none;border:0;border-radius:var(--bs-border-radius-sm);cursor:pointer;transition:color .15s,background-color .15s}",
            ".nav-link:hover{color:var(--bs-emphasis-color);background:var(--bs-secondary-bg);text-decoration:none}.nav-link.active{color:var(--bs-primary)}.nav-link.disabled,.nav-link:disabled{opacity:.5;pointer-events:none}",
            ".nav-pills .nav-link.active{color:#fff;background:var(--bs-primary)}.nav-fill>.nav-link,.nav-fill .nav-item{flex:1 1 auto;text-align:center}.nav-justified .nav-item{flex:1 1 0;text-align:center}",
            ".nav-tabs{gap:0;border-bottom:1px solid var(--bs-border-color)}.nav-tabs .nav-link{margin-bottom:-1px;border:1px solid transparent;border-radius:var(--bs-border-radius-sm) var(--bs-border-radius-sm) 0 0}",
            ".nav-tabs .nav-link.active{color:var(--bs-emphasis-color);background:var(--bs-surface);border-color:var(--bs-border-color) var(--bs-border-color) var(--bs-surface)}",
            ".tab-content>.tab-pane{display:none}.tab-content>.active{display:block}",
            ".breadcrumb{display:flex;flex-wrap:wrap;padding:0;margin:0 0 1rem;list-style:none;color:var(--bs-secondary-color)}.breadcrumb-item+.breadcrumb-item::before{content:\"/\";padding:0 .5rem;color:var(--bs-tertiary-color)}",
            ".pagination{display:flex;gap:.25rem;padding:0;margin:0;list-style:none}.page-link{display:block;padding:.4rem .75rem;color:var(--bs-body-color);background:var(--bs-surface);border:1px solid var(--bs-border-color);border-radius:var(--bs-border-radius-sm);text-decoration:none;cursor:pointer}",
            ".page-link:hover{background:var(--bs-tertiary-bg);text-decoration:none}.page-item.active .page-link{color:#fff;background:var(--bs-primary);border-color:var(--bs-primary)}.page-item.disabled .page-link{opacity:.5;pointer-events:none}",
            // Cards
            ".card{position:relative;display:flex;flex-direction:column;min-width:0;word-wrap:break-word;background:var(--bs-surface);border:1px solid var(--bs-border-color);border-radius:var(--bs-border-radius-lg);box-shadow:var(--bs-shadow-sm)}",
            ".card-body{flex:1 1 auto;padding:1.25rem}.card-title{margin-bottom:.5rem;font-weight:650}.card-subtitle{margin-top:-.25rem;margin-bottom:.5rem;color:var(--bs-secondary-color)}.card-text:last-child{margin-bottom:0}",
            ".card-header,.card-footer{padding:.85rem 1.25rem;background:var(--bs-tertiary-bg);border:0 solid var(--bs-border-color)}.card-header{border-bottom-width:1px;font-weight:600;border-radius:var(--bs-border-radius-lg) var(--bs-border-radius-lg) 0 0}",
            ".card-footer{border-top-width:1px;border-radius:0 0 var(--bs-border-radius-lg) var(--bs-border-radius-lg)}.card-img-top{display:block;width:100%;border-radius:var(--bs-border-radius-lg) var(--bs-border-radius-lg) 0 0}.card-link+.card-link{margin-left:1rem}",
            ".card-group{display:flex;flex-wrap:wrap;gap:1rem}.card-group>.card{flex:1 0 0%}",
            // Buttons
            ".btn{display:inline-flex;align-items:center;justify-content:center;gap:.4rem;padding:.5rem 1rem;font-size:.95rem;font-weight:550;line-height:1.4;color:var(--bs-body-color);text-align:center;text-decoration:none;vertical-align:middle;cursor:pointer;user-select:none;background:transparent;border:1px solid transparent;border-radius:var(--bs-border-radius);transition:background-color .15s,border-color .15s,color .15s,box-shadow .15s,filter .15s}",
            ".btn:hover{text-decoration:none}.btn:focus-visible{outline:0;box-shadow:var(--bs-focus-ring)}.btn:active{transform:translateY(1px)}.btn:disabled,.btn.disabled{opacity:.55;pointer-events:none}",
            ".btn-link{color:var(--bs-link-color);background:none;border:0;padding-left:.25rem;padding-right:.25rem}.btn-link:hover{text-decoration:underline}",
            ".btn-sm{padding:.3rem .65rem;font-size:.85rem;border-radius:var(--bs-border-radius-sm)}.btn-lg{padding:.7rem 1.4rem;font-size:1.1rem;border-radius:var(--bs-border-radius-lg)}",
            ".btn-close{position:relative;box-sizing:content-box;width:1em;height:1em;padding:.25em;color:inherit;background:transparent;border:0;border-radius:.375rem;opacity:.5;cursor:pointer}",
            ".btn-close::before{content:\"✕\";position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:.9em}.btn-close:hover{opacity:.85}.btn-close-white{color:#fff}",
            ".btn-group,.btn-group-vertical{position:relative;display:inline-flex;vertical-align:middle}.btn-group-vertical{flex-direction:column}",
            ".btn-group>.btn:not(:first-child){margin-left:-1px;border-top-left-radius:0;border-bottom-left-radius:0}.btn-group>.btn:not(:last-child){border-top-right-radius:0;border-bottom-right-radius:0}",
            ".btn-check{position:absolute;clip:rect(0,0,0,0);pointer-events:none}.btn-check:checked+.btn{color:#fff;background:var(--bs-primary);border-color:var(--bs-primary)}",
            // Forms
            ".form-label{margin-bottom:.4rem;font-size:.92rem;font-weight:550}.col-form-label{padding-top:.55rem;padding-bottom:.55rem;font-weight:550}.form-text{margin-top:.25rem;font-size:.85rem;color:var(--bs-secondary-color)}",
            ".form-control,.form-select{display:block;width:100%;padding:.55rem .8rem;font-size:1rem;line-height:1.45;color:var(--bs-body-color);background-color:var(--bs-surface);background-clip:padding-box;border:1px solid var(--bs-border-color);border-radius:var(--bs-border-radius);transition:border-color .15s,box-shadow .15s;appearance:none}",
            ".form-control:focus,.form-select:focus{outline:0;border-color:rgba(var(--bs-primary-rgb),.6);box-shadow:var(--bs-focus-ring)}.form-control::placeholder{color:var(--bs-tertiary-color)}.form-control:disabled,.form-select:disabled{background-color:var(--bs-secondary-bg)}",
            "textarea.form-control{min-height:5rem;resize:vertical}.form-control-sm,.form-select-sm{padding:.3rem .6rem;font-size:.875rem;border-radius:var(--bs-border-radius-sm)}.form-control-lg,.form-select-lg{padding:.75rem 1rem;font-size:1.15rem;border-radius:var(--bs-border-radius-lg)}",
            ".form-control-color{width:3rem;height:2.6rem;padding:.3rem}.form-control-plaintext{display:block;width:100%;padding:.55rem 0;background:transparent;border:0}",
            ".form-select{padding-right:2.25rem;background-image:url(\"data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3e%3cpath fill='none' stroke='%2364748b' stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='m2 5 6 6 6-6'/%3e%3c/svg%3e\");background-repeat:no-repeat;background-position:right .75rem center;background-size:12px 12px}",
            ".form-check{display:flex;align-items:center;gap:.5rem;min-height:1.5rem;margin-bottom:.25rem}.form-check-inline{display:inline-flex;margin-right:1rem}.form-check-label{cursor:pointer}",
            ".form-check-input{flex-shrink:0;width:1.1rem;height:1.1rem;margin:0;accent-color:var(--bs-primary);cursor:pointer}",
            ".form-switch .form-check-input{position:relative;width:2.1rem;height:1.2rem;appearance:none;background:var(--bs-secondary-bg);border:1px solid var(--bs-border-color);border-radius:2rem;transition:background-color .15s}",
            ".form-switch .form-check-input::after{content:\"\";position:absolute;top:1px;left:1px;width:calc(1.2rem - 4px);height:calc(1.2rem - 4px);background:#fff;border-radius:50%;box-shadow:0 1px 2px rgba(0,0,0,.25);transition:transform .15s}",
            ".form-switch .form-check-input:checked{background:var(--bs-primary);border-color:var(--bs-primary)}.form-switch .form-check-input:checked::after{transform:translateX(.9rem)}",
            ".form-range{width:100%;accent-color:var(--bs-primary)}.form-floating{position:relative}.form-floating>.form-control,.form-floating>.form-select{padding-top:1.45rem;padding-bottom:.4rem}",
            ".form-floating>label{position:absolute;top:.35rem;left:.8rem;font-size:.75rem;color:var(--bs-secondary-color);pointer-events:none}",
            ".input-group{position:relative;display:flex;flex-wrap:wrap;align-items:stretch;width:100%}.input-group>.form-control,.input-group>.form-select{position:relative;flex:1 1 auto;width:1%;min-width:0}",
            ".input-group>:not(:first-child){margin-left:-1px;border-top-left-radius:0;border-bottom-left-radius:0}.input-group>:not(:last-child){border-top-right-radius:0;border-bottom-right-radius:0}",
            ".input-group-text{display:flex;align-items:center;padding:.55rem .8rem;color:var(--bs-secondary-color);white-space:nowrap;background:var(--bs-tertiary-bg);border:1px solid var(--bs-border-color);border-radius:var(--bs-border-radius)}",
            ".is-invalid{border-color:var(--bs-danger)!important}.is-valid{border-color:var(--bs-success)!important}.invalid-feedback,.valid-feedback{display:none;margin-top:.25rem;font-size:.85rem}",
            ".invalid-feedback{color:var(--bs-danger)}.valid-feedback{color:var(--bs-success)}.is-invalid~.invalid-feedback,.is-valid~.valid-feedback,.invalid-feedback.d-block,.valid-feedback.d-block{display:block}",
            // Lists and tables
            ".list-group{display:flex;flex-direction:column;padding:0;margin:0;overflow:hidden;list-style:none;background:var(--bs-surface);border:1px solid var(--bs-border-color);border-radius:var(--bs-border-radius-lg)}",
            ".list-group:empty{display:none}.list-group-item{position:relative;display:block;padding:.8rem 1.1rem;color:var(--bs-body-color);text-decoration:none;background:transparent;border:0;border-top:1px solid var(--bs-border-color)}.list-group-item:first-child{border-top:0}",
            ".list-group-item-action{width:100%;text-align:left;cursor:pointer}.list-group-item-action:hover{background:var(--bs-tertiary-bg);text-decoration:none}",
            ".list-group-item.active{color:#fff;background:var(--bs-primary)}.list-group-item.disabled{color:var(--bs-tertiary-color);pointer-events:none}.list-group-flush{background:transparent;border:0;border-radius:0}",
            ".list-group-horizontal{flex-direction:row}.list-group-horizontal>.list-group-item{border-top:0;border-left:1px solid var(--bs-border-color)}.list-group-horizontal>.list-group-item:first-child{border-left:0}",
            ".list-unstyled,.list-inline{padding-left:0;list-style:none}.list-inline-item{display:inline-block}.list-inline-item:not(:last-child){margin-right:.5rem}",
            ".table{width:100%;margin-bottom:1rem;color:var(--bs-body-color);vertical-align:top;background:var(--bs-surface)}.table>:not(caption)>*>*{padding:.7rem .9rem;text-align:left;border-bottom:1px solid var(--bs-border-color)}",
            ".table>thead>tr>*{font-size:.78rem;font-weight:650;text-transform:uppercase;letter-spacing:.04em;color:var(--bs-secondary-color);background:var(--bs-tertiary-bg)}",
            ".table-sm>:not(caption)>*>*{padding:.4rem .6rem}.table-striped>tbody>tr:nth-of-type(odd)>*{background:var(--bs-tertiary-bg)}.table-hover>tbody>tr:hover>*{background:rgba(var(--bs-primary-rgb),.05)}",
            ".table-bordered>:not(caption)>*>*{border:1px solid var(--bs-border-color)}.table-borderless>:not(caption)>*>*{border:0}.table-responsive{overflow-x:auto}",
            ".table-dark>:not(caption)>*>*,thead.table-dark>tr>*,.table>thead.table-dark>tr>*{color:#fff;background:var(--bs-dark)}caption{padding:.5rem 0;color:var(--bs-secondary-color);text-align:left}",
            // Badges, alerts, progress and spinners
            ".badge{display:inline-flex;align-items:center;gap:.25rem;padding:.32em .62em;font-size:.75em;font-weight:650;line-height:1;color:#fff;white-space:nowrap;vertical-align:baseline;background:var(--bs-secondary);border-radius:var(--bs-border-radius-pill)}",
            ".alert{position:relative;padding:.85rem 1.1rem;margin-bottom:1rem;border:1px solid transparent;border-radius:var(--bs-border-radius)}.alert-heading{color:inherit}.alert-link{font-weight:700;color:inherit}",
            ".alert-dismissible{padding-right:3rem}.alert-dismissible .btn-close{position:absolute;top:.75rem;right:.85rem}",
            ".progress,.progress-stacked{display:flex;height:.75rem;overflow:hidden;font-size:.7rem;background:var(--bs-secondary-bg);border-radius:var(--bs-border-radius-pill)}",
            ".progress-bar{display:flex;flex-direction:column;justify-content:center;overflow:hidden;color:#fff;text-align:center;white-space:nowrap;background:var(--bs-primary);transition:width .4s ease}",
            ".progress-bar-striped{background-image:linear-gradient(45deg,rgba(255,255,255,.15) 25%,transparent 25%,transparent 50%,rgba(255,255,255,.15) 50%,rgba(255,255,255,.15) 75%,transparent 75%,transparent);background-size:1rem 1rem}",
            ".progress-bar-animated{animation:kit-stripes 1s linear infinite}@keyframes kit-stripes{0%{background-position-x:1rem}}",
            ".spinner-border{display:inline-block;width:2rem;height:2rem;vertical-align:-.125em;border:.25em solid currentcolor;border-right-color:transparent;border-radius:50%;animation:kit-spin .75s linear infinite}",
            ".spinner-border-sm{width:1rem;height:1rem;border-width:.2em}.spinner-grow{display:inline-block;width:2rem;height:2rem;background:currentcolor;border-radius:50%;opacity:0;animation:kit-grow .75s linear infinite}",
            "@keyframes kit-spin{to{transform:rotate(360deg)}}@keyframes kit-grow{0%{transform:scale(0)}50%{opacity:1;transform:none}}",
            // Things that open and close. Without Bootstrap's script, app.js opens them with a class.
            ".modal{position:fixed;inset:0;z-index:1050;display:none;align-items:center;justify-content:center;padding:1rem;overflow-y:auto;background:rgba(15,23,42,.45)}",
            ".modal.show,.modal.d-block,.modal.open,.modal.is-open,.modal.active{display:flex!important}.modal-backdrop{display:none}",
            ".modal-dialog{width:100%;max-width:500px;margin:auto}.modal-sm{max-width:320px}.modal-lg{max-width:800px}.modal-xl{max-width:1100px}",
            ".modal-content{display:flex;flex-direction:column;overflow:hidden;background:var(--bs-surface);border:1px solid var(--bs-border-color);border-radius:var(--bs-border-radius-xl);box-shadow:var(--bs-shadow-lg)}",
            ".modal-header{display:flex;align-items:center;justify-content:space-between;padding:1rem 1.25rem;border-bottom:1px solid var(--bs-border-color)}.modal-title{margin:0;font-size:1.15rem;font-weight:650}.modal-body{padding:1.25rem}",
            ".modal-footer{display:flex;flex-wrap:wrap;justify-content:flex-end;gap:.5rem;padding:.85rem 1.25rem;background:var(--bs-tertiary-bg);border-top:1px solid var(--bs-border-color)}",
            ".dropdown,.dropup,.dropend,.dropstart{position:relative}.dropdown-menu{position:absolute;z-index:1000;display:none;min-width:10rem;padding:.4rem;margin:.25rem 0 0;list-style:none;background:var(--bs-surface);border:1px solid var(--bs-border-color);border-radius:var(--bs-border-radius);box-shadow:var(--bs-shadow)}",
            ".dropdown-menu.show{display:block}.dropdown-menu-end{right:0}.dropdown-item{display:block;width:100%;padding:.4rem .75rem;color:var(--bs-body-color);text-align:left;text-decoration:none;background:none;border:0;border-radius:var(--bs-border-radius-sm);cursor:pointer}",
            ".dropdown-item:hover{background:var(--bs-tertiary-bg);text-decoration:none}.dropdown-item.active{color:#fff;background:var(--bs-primary)}.dropdown-divider{height:0;margin:.4rem 0;border-top:1px solid var(--bs-border-color)}",
            ".dropdown-header{display:block;padding:.4rem .75rem;font-size:.8rem;color:var(--bs-secondary-color)}",
            ".dropdown-toggle::after{content:\"\";display:inline-block;margin-left:.35em;vertical-align:.2em;border-top:.3em solid;border-right:.3em solid transparent;border-left:.3em solid transparent}",
            ".collapse:not(.show){display:none}.accordion{border-radius:var(--bs-border-radius-lg)}.accordion-item{background:var(--bs-surface);border:1px solid var(--bs-border-color)}.accordion-item+.accordion-item{border-top:0}",
            ".accordion-item:first-child{border-radius:var(--bs-border-radius-lg) var(--bs-border-radius-lg) 0 0}.accordion-item:last-child{border-radius:0 0 var(--bs-border-radius-lg) var(--bs-border-radius-lg)}",
            ".accordion-header{margin:0}.accordion-button{display:flex;align-items:center;width:100%;padding:.9rem 1.1rem;font-size:1rem;font-weight:600;color:inherit;text-align:left;background:none;border:0;cursor:pointer}.accordion-body{padding:.9rem 1.1rem}",
            ".toast-container{position:fixed;z-index:1090;display:flex;flex-direction:column;gap:.5rem;padding:1rem}.toast{width:320px;max-width:100%;background:var(--bs-surface);border:1px solid var(--bs-border-color);border-radius:var(--bs-border-radius);box-shadow:var(--bs-shadow)}",
            ".toast:not(.show){display:none}.toast-header{display:flex;align-items:center;gap:.5rem;padding:.5rem .75rem;font-weight:600;border-bottom:1px solid var(--bs-border-color)}.toast-body{padding:.75rem}",
            ".offcanvas{position:fixed;top:0;bottom:0;z-index:1045;display:none;width:320px;max-width:100%;padding:1rem;background:var(--bs-surface);box-shadow:var(--bs-shadow-lg)}.offcanvas.show{display:block}.offcanvas-start{left:0}.offcanvas-end{right:0}",
            ".tooltip,.popover{display:none}.placeholder{display:inline-block;min-height:1em;vertical-align:middle;background:currentcolor;opacity:.4;border-radius:.25rem}",
            ".img-fluid{max-width:100%;height:auto}.img-thumbnail{max-width:100%;height:auto;padding:.25rem;background:var(--bs-surface);border:1px solid var(--bs-border-color);border-radius:var(--bs-border-radius)}",
            ".figure{display:inline-block}.figure-caption{font-size:.875em;color:var(--bs-secondary-color)}",
            ".ratio{position:relative;width:100%}.ratio::before{display:block;padding-top:var(--bs-aspect-ratio);content:\"\"}.ratio>*{position:absolute;top:0;left:0;width:100%;height:100%}",
            ".ratio-1x1{--bs-aspect-ratio:100%}.ratio-4x3{--bs-aspect-ratio:75%}.ratio-16x9{--bs-aspect-ratio:56.25%}.ratio-21x9{--bs-aspect-ratio:42.857%}",
            ".vr{display:inline-block;align-self:stretch;width:1px;min-height:1em;background:currentcolor;opacity:.25}.clearfix::after{display:block;clear:both;content:\"\"}",
            ".visually-hidden,.visually-hidden-focusable:not(:focus){position:absolute!important;width:1px!important;height:1px!important;padding:0!important;margin:-1px!important;overflow:hidden!important;clip:rect(0,0,0,0)!important;white-space:nowrap!important;border:0!important}",
        ])
        return rules.joined(separator: "\n") + "\n"
    }

    /// The utility classes, which come in families too regular to write out by hand.
    private static var utilities: String {
        var rules: [String] = []
        func add(_ selector: String, _ body: String) { rules.append(".\(selector){\(body)}") }

        for color in colors {
            let text = color.darkText ? "#1e293b" : "#fff"
            add("text-\(color.name)", "color:var(--bs-\(color.name))!important")
            add("text-\(color.name)-emphasis", "color:var(--bs-\(color.name)-text-emphasis)!important")
            add("bg-\(color.name)", "background-color:var(--bs-\(color.name))!important")
            add("bg-\(color.name)-subtle", "background-color:rgba(var(--bs-\(color.name)-rgb),.12)!important")
            add("text-bg-\(color.name)", "color:\(text)!important;background-color:var(--bs-\(color.name))!important")
            add("border-\(color.name)", "border-color:var(--bs-\(color.name))!important")
            add("border-\(color.name)-subtle", "border-color:rgba(var(--bs-\(color.name)-rgb),.3)!important")
            add("link-\(color.name)", "color:var(--bs-\(color.name))!important")
            add("btn-\(color.name)", "color:\(text);background-color:var(--bs-\(color.name));border-color:var(--bs-\(color.name))")
            add("btn-\(color.name):hover", "color:\(text);filter:brightness(.92)")
            add("btn-outline-\(color.name)", "color:var(--bs-\(color.name)-text-emphasis);background-color:transparent;border-color:rgba(var(--bs-\(color.name)-rgb),.55)")
            add("btn-outline-\(color.name):hover", "color:\(text);background-color:var(--bs-\(color.name));border-color:var(--bs-\(color.name))")
            add("alert-\(color.name)", "color:var(--bs-\(color.name)-text-emphasis);background-color:rgba(var(--bs-\(color.name)-rgb),.1);border-color:rgba(var(--bs-\(color.name)-rgb),.25)")
            add("list-group-item-\(color.name)", "color:var(--bs-\(color.name)-text-emphasis);background-color:rgba(var(--bs-\(color.name)-rgb),.1)")
            add("table-\(color.name)>*>*,.table-\(color.name)", "background-color:rgba(var(--bs-\(color.name)-rgb),.1)")
        }
        rules.append(contentsOf: [
            ".text-muted,.text-body-secondary{color:var(--bs-secondary-color)!important}.text-body-tertiary{color:var(--bs-tertiary-color)!important}",
            ".text-body{color:var(--bs-body-color)!important}.text-body-emphasis{color:var(--bs-emphasis-color)!important}.text-white{color:#fff!important}.text-black{color:#000!important}",
            ".text-white-50{color:rgba(255,255,255,.6)!important}.text-black-50{color:rgba(0,0,0,.5)!important}.text-reset{color:inherit!important}",
            ".bg-white{background-color:#fff!important}.bg-black{background-color:#000!important}.bg-body{background-color:var(--bs-body-bg)!important}",
            ".bg-body-secondary{background-color:var(--bs-secondary-bg)!important}.bg-body-tertiary{background-color:var(--bs-tertiary-bg)!important}.bg-transparent{background-color:transparent!important}",
            ".bg-gradient{background-image:linear-gradient(180deg,rgba(255,255,255,.15),rgba(255,255,255,0))!important}",
            ".border{border:1px solid var(--bs-border-color)!important}.border-0{border:0!important}",
            ".border-top{border-top:1px solid var(--bs-border-color)!important}.border-bottom{border-bottom:1px solid var(--bs-border-color)!important}",
            ".border-start{border-left:1px solid var(--bs-border-color)!important}.border-end{border-right:1px solid var(--bs-border-color)!important}",
            ".border-top-0{border-top:0!important}.border-bottom-0{border-bottom:0!important}.border-start-0{border-left:0!important}.border-end-0{border-right:0!important}",
            ".border-white{border-color:#fff!important}.border-1{border-width:1px!important}.border-2{border-width:2px!important}.border-3{border-width:3px!important}.border-4{border-width:4px!important}.border-5{border-width:5px!important}",
            ".rounded{border-radius:var(--bs-border-radius)!important}.rounded-0{border-radius:0!important}.rounded-1{border-radius:var(--bs-border-radius-sm)!important}",
            ".rounded-2{border-radius:var(--bs-border-radius)!important}.rounded-3{border-radius:var(--bs-border-radius-lg)!important}.rounded-4{border-radius:var(--bs-border-radius-xl)!important}",
            ".rounded-5{border-radius:2rem!important}.rounded-circle{border-radius:50%!important}.rounded-pill{border-radius:var(--bs-border-radius-pill)!important}",
            ".rounded-top{border-top-left-radius:var(--bs-border-radius)!important;border-top-right-radius:var(--bs-border-radius)!important}",
            ".rounded-bottom{border-bottom-left-radius:var(--bs-border-radius)!important;border-bottom-right-radius:var(--bs-border-radius)!important}",
            ".shadow{box-shadow:var(--bs-shadow)!important}.shadow-sm{box-shadow:var(--bs-shadow-sm)!important}.shadow-lg{box-shadow:var(--bs-shadow-lg)!important}.shadow-none{box-shadow:none!important}",
            ".text-start{text-align:left!important}.text-center{text-align:center!important}.text-end{text-align:right!important}",
            ".text-wrap{white-space:normal!important}.text-nowrap{white-space:nowrap!important}.text-break{word-wrap:break-word!important;word-break:break-word!important}",
            ".text-truncate{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
            ".text-lowercase{text-transform:lowercase!important}.text-uppercase{text-transform:uppercase!important}.text-capitalize{text-transform:capitalize!important}",
            ".text-decoration-none{text-decoration:none!important}.text-decoration-underline{text-decoration:underline!important}.text-decoration-line-through{text-decoration:line-through!important}",
            ".fw-light{font-weight:300!important}.fw-normal{font-weight:400!important}.fw-medium{font-weight:500!important}.fw-semibold{font-weight:600!important}.fw-bold{font-weight:700!important}.fw-bolder{font-weight:800!important}",
            ".fst-italic{font-style:italic!important}.fst-normal{font-style:normal!important}.font-monospace{font-family:var(--bs-font-monospace)!important}",
            ".fs-1{font-size:2.1rem!important}.fs-2{font-size:1.7rem!important}.fs-3{font-size:1.4rem!important}.fs-4{font-size:1.2rem!important}.fs-5{font-size:1.05rem!important}.fs-6{font-size:.95rem!important}",
            ".lh-1{line-height:1!important}.lh-sm{line-height:1.25!important}.lh-base{line-height:1.55!important}.lh-lg{line-height:2!important}",
            ".w-25{width:25%!important}.w-50{width:50%!important}.w-75{width:75%!important}.w-100{width:100%!important}.w-auto{width:auto!important}.mw-100{max-width:100%!important}.vw-100{width:100vw!important}",
            ".h-25{height:25%!important}.h-50{height:50%!important}.h-75{height:75%!important}.h-100{height:100%!important}.h-auto{height:auto!important}.mh-100{max-height:100%!important}",
            ".vh-100{height:100vh!important}.min-vh-100{min-height:100vh!important}.min-w-0{min-width:0!important}",
            ".position-static{position:static!important}.position-relative{position:relative!important}.position-absolute{position:absolute!important}.position-fixed{position:fixed!important}.position-sticky{position:sticky!important}",
            ".top-0{top:0!important}.top-50{top:50%!important}.top-100{top:100%!important}.bottom-0{bottom:0!important}.bottom-50{bottom:50%!important}",
            ".start-0{left:0!important}.start-50{left:50%!important}.start-100{left:100%!important}.end-0{right:0!important}.end-50{right:50%!important}",
            ".translate-middle{transform:translate(-50%,-50%)!important}.translate-middle-x{transform:translateX(-50%)!important}.translate-middle-y{transform:translateY(-50%)!important}",
            ".fixed-top{position:fixed;top:0;right:0;left:0;z-index:1030}.fixed-bottom{position:fixed;right:0;bottom:0;left:0;z-index:1030}.sticky-top{position:sticky;top:0;z-index:1020}.sticky-bottom{position:sticky;bottom:0;z-index:1020}",
            ".overflow-auto{overflow:auto!important}.overflow-hidden{overflow:hidden!important}.overflow-visible{overflow:visible!important}.overflow-scroll{overflow:scroll!important}",
            ".overflow-x-auto{overflow-x:auto!important}.overflow-y-auto{overflow-y:auto!important}",
            ".opacity-0{opacity:0!important}.opacity-25{opacity:.25!important}.opacity-50{opacity:.5!important}.opacity-75{opacity:.75!important}.opacity-100{opacity:1!important}",
            ".user-select-all{user-select:all!important}.user-select-auto{user-select:auto!important}.user-select-none{user-select:none!important}.pe-none{pointer-events:none!important}.pe-auto{pointer-events:auto!important}",
            ".cursor-pointer{cursor:pointer!important}.float-start{float:left!important}.float-end{float:right!important}.float-none{float:none!important}",
            ".object-fit-cover{object-fit:cover!important}.object-fit-contain{object-fit:contain!important}",
            ".z-0{z-index:0!important}.z-1{z-index:1!important}.z-2{z-index:2!important}.z-3{z-index:3!important}",
            ".align-baseline{vertical-align:baseline!important}.align-top{vertical-align:top!important}.align-middle{vertical-align:middle!important}.align-bottom{vertical-align:bottom!important}",
            ".flex-fill{flex:1 1 auto!important}.flex-grow-0{flex-grow:0!important}.flex-grow-1{flex-grow:1!important}.flex-shrink-0{flex-shrink:0!important}.flex-shrink-1{flex-shrink:1!important}",
            ".flex-wrap{flex-wrap:wrap!important}.flex-nowrap{flex-wrap:nowrap!important}",
            ".align-self-start{align-self:flex-start!important}.align-self-end{align-self:flex-end!important}.align-self-center{align-self:center!important}.align-self-stretch{align-self:stretch!important}",
            ".align-content-start{align-content:flex-start!important}.align-content-center{align-content:center!important}.align-content-between{align-content:space-between!important}",
            ".order-first{order:-1!important}.order-last{order:6!important}",
        ])
        for (key, value) in spaces {
            add("gap-\(key)", "gap:\(value)!important")
            add("row-gap-\(key)", "row-gap:\(value)!important")
            add("column-gap-\(key)", "column-gap:\(value)!important")
            add("order-\(key)", "order:\(key)!important")
            // Gutters, between the columns of a row.
            add("g-\(key),.gx-\(key)", "--bs-gutter-x:\(value)")
            add("g-\(key),.gy-\(key)", "--bs-gutter-y:\(value)")
        }
        let sides: [(String, [String])] = [("", [""]), ("t", ["-top"]), ("b", ["-bottom"]), ("s", ["-left"]), ("e", ["-right"]), ("x", ["-left", "-right"]), ("y", ["-top", "-bottom"])]
        for (property, letter) in [("margin", "m"), ("padding", "p")] {
            for (side, edges) in sides {
                for (key, value) in spaces + (property == "margin" ? [("auto", "auto")] : []) {
                    add("\(letter)\(side)-\(key)", edges.map { "\(property)\($0):\(value)!important" }.joined(separator: ";"))
                }
            }
        }
        rules.append(contentsOf: responsive(prefix: ""))
        for (name, width) in breakpoints {
            rules.append("@media (min-width:\(width)px){" + responsive(prefix: "-\(name)").joined() + "}")
        }
        return rules.joined(separator: "\n") + "\n"
    }

    /// What changes with the width of the window: columns, display, direction and alignment.
    private static func responsive(prefix: String) -> [String] {
        var rules: [String] = []
        func add(_ selector: String, _ body: String) { rules.append(".\(selector){\(body)}") }
        add("col\(prefix)", "flex:1 0 0%")
        add("col\(prefix)-auto", "flex:0 0 auto;width:auto")
        for span in 1...12 {
            add("col\(prefix)-\(span)", "flex:0 0 auto;width:\(percent(Double(span) / 12))")
        }
        for span in 0...11 {
            add("offset\(prefix)-\(span)", "margin-left:\(span == 0 ? "0" : percent(Double(span) / 12))")
        }
        for count in 1...6 {
            add("row-cols\(prefix)-\(count)>*", "flex:0 0 auto;width:\(percent(1 / Double(count)))")
        }
        for display in ["none", "inline", "inline-block", "block", "grid", "inline-grid", "flex", "inline-flex", "table", "table-cell"] {
            add("d\(prefix)-\(display)", "display:\(display)!important")
        }
        for direction in ["row", "column", "row-reverse", "column-reverse"] {
            add("flex\(prefix)-\(direction)", "flex-direction:\(direction)!important")
        }
        for (name, value) in [("start", "flex-start"), ("end", "flex-end"), ("center", "center"), ("between", "space-between"), ("around", "space-around"), ("evenly", "space-evenly")] {
            add("justify-content\(prefix)-\(name)", "justify-content:\(value)!important")
        }
        for (name, value) in [("start", "flex-start"), ("end", "flex-end"), ("center", "center"), ("baseline", "baseline"), ("stretch", "stretch")] {
            add("align-items\(prefix)-\(name)", "align-items:\(value)!important")
        }
        if !prefix.isEmpty {
            for (name, value) in [("start", "left"), ("center", "center"), ("end", "right")] {
                add("text\(prefix)-\(name)", "text-align:\(value)!important")
            }
        }
        return rules
    }

    private static func percent(_ fraction: Double) -> String {
        let value = (fraction * 100_000).rounded() / 1_000
        return value == value.rounded() ? "\(Int(value))%" : "\(value)%"
    }
}
