// Shared motion for the pages around the landing page: the reading-progress
// ink line, the nav's border on scroll, reveal-on-scroll, the pointer glow on
// cards, and the table of contents that follows the section being read.
(function () {
  var nav = document.querySelector('.topnav'), bar = document.querySelector('.progress');
  function onScroll() {
    var h = document.documentElement, p = h.scrollTop / Math.max(1, h.scrollHeight - h.clientHeight);
    if (bar) bar.style.transform = 'scaleX(' + p + ')';
    if (nav) nav.classList.toggle('scrolled', h.scrollTop > 10);
  }
  addEventListener('scroll', onScroll, { passive: true }); onScroll();

  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
  }, { threshold: 0.12 });
  document.querySelectorAll('.reveal, .stagger').forEach(function (el) { io.observe(el); });

  document.querySelectorAll('.card').forEach(function (el) {
    el.addEventListener('pointermove', function (ev) {
      var r = el.getBoundingClientRect();
      el.style.setProperty('--mx', (ev.clientX - r.left) + 'px'); el.style.setProperty('--my', (ev.clientY - r.top) + 'px');
    });
  });

  // Table of contents: built from the document's own sections, and marks the
  // one being read.
  var toc = document.querySelector('.toc'), secs = document.querySelectorAll('.sheet section[id]');
  if (toc && secs.length) {
    var links = {};
    secs.forEach(function (s) {
      var a = document.createElement('a'); a.href = '#' + s.id;
      a.textContent = s.querySelector('h2').textContent.replace(/^\s*\d+\s*/, '');
      toc.appendChild(a); links[s.id] = a;
    });
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        Object.keys(links).forEach(function (k) { links[k].classList.toggle('on', k === e.target.id); });
        var on = links[e.target.id];
        if (on && toc.scrollWidth > toc.clientWidth) toc.scrollTo({ left: on.offsetLeft - 16, behavior: 'smooth' });
      });
    }, { rootMargin: '-30% 0px -60% 0px' });
    secs.forEach(function (s) { spy.observe(s); });
  }
})();
