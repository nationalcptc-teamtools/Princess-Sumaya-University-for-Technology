// Global keyboard shortcut for the instant-search palette. The palette
// component registers itself with a DotNetObjectReference; we call its
// [JSInvokable] Toggle() method on Ctrl-K / Cmd-K.
//
// Keeping it global (not per-page) so the shortcut works no matter which
// route you're on.
window.jvisionSearch = (function () {
  var _dotnet = null;

  function onKeyDown(e) {
    var isK = (e.key === 'k' || e.key === 'K');
    if (!isK) return;
    if (!(e.ctrlKey || e.metaKey)) return;
    e.preventDefault();
    if (_dotnet) _dotnet.invokeMethodAsync('Toggle');
  }

  return {
    register: function (dotnetRef) {
      _dotnet = dotnetRef;
      window.addEventListener('keydown', onKeyDown);
    },
    unregister: function () {
      window.removeEventListener('keydown', onKeyDown);
      _dotnet = null;
    },
    focus: function (id) {
      // Called after opening the palette so the input gets focus.
      var el = document.getElementById(id);
      if (el) { el.focus(); el.select && el.select(); }
    }
  };
})();
