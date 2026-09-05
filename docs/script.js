const header = document.querySelector('[data-header]');
const reveals = document.querySelectorAll('.reveal');
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const updateHeader = () => header?.classList.toggle('scrolled', window.scrollY > 16);
updateHeader();
window.addEventListener('scroll', updateHeader, { passive: true });

if (reduceMotion || !('IntersectionObserver' in window)) {
  reveals.forEach((element) => element.classList.add('visible'));
} else {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('visible');
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.12, rootMargin: '0px 0px -30px' });
  reveals.forEach((element) => observer.observe(element));
}

document.querySelectorAll('[data-year]').forEach((element) => {
  element.textContent = new Date().getFullYear();
});

if (!reduceMotion && window.matchMedia('(pointer: fine)').matches) {
  document.querySelectorAll('.nav, .button, .status-chip, .eyebrow, .glass-label, .journey span, .mini-switcher, .tag-row span').forEach((element) => {
    element.addEventListener('pointermove', (event) => {
      const bounds = element.getBoundingClientRect();
      const x = event.clientX - bounds.left;
      const y = event.clientY - bounds.top;
      const ratioX = x / bounds.width - 0.5;
      const ratioY = y / bounds.height - 0.5;
      element.style.setProperty('--gx', `${x}px`);
      element.style.setProperty('--gy', `${y}px`);
      element.style.setProperty('--glass-angle', `${135 + ratioX * 36}deg`);
      element.style.setProperty('--glass-shift-x', `${ratioX * 9}px`);
      element.style.setProperty('--glass-shift-y', `${ratioY * 7}px`);
    }, { passive: true });
    element.addEventListener('pointerleave', () => {
      element.style.removeProperty('--gx');
      element.style.removeProperty('--gy');
      element.style.removeProperty('--glass-angle');
      element.style.removeProperty('--glass-shift-x');
      element.style.removeProperty('--glass-shift-y');
    }, { passive: true });
  });
}
