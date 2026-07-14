/* ═══════════════════════════════════════════════════════════════════════════
   CARDCOMPASS — Interactive Layer
   
   Modules:
     1. Particle Canvas System (neural-network constellation)
     2. 3D Card Mouse Tracking (perspective tilt + shine)
     3. Magnetic Cursor Effect (buttons attract pointer)
     4. Scroll Observer Fallback (for browsers w/o scroll-driven animations)
     5. Animated Counters (count-up on scroll)
     6. Terminal Typing Animation (sequential line reveal)
     7. Navigation Scroll State
     8. Smooth Scroll + Mobile Menu
   ═══════════════════════════════════════════════════════════════════════════ */

(function () {
  'use strict';

  // ─── Respect reduced motion preference ───
  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;


  /* ═══════════════════════════════════════════
     1. PARTICLE CANVAS SYSTEM
     A constellation of floating orbs in brand
     colors, connected by fading lines when near.
     Mouse gently repels nearby particles.
     ═══════════════════════════════════════════ */
  const canvas = document.getElementById('particleCanvas');
  if (canvas && !prefersReducedMotion) {
    const ctx = canvas.getContext('2d');
    let width, height, particles, mouse, animationId;
    const COLORS = [
      'rgba(0, 245, 255, ',   // cyan
      'rgba(139, 92, 246, ',  // purple
      'rgba(255, 0, 127, ',   // magenta
      'rgba(255, 215, 0, ',   // gold (rare)
    ];
    const COLOR_WEIGHTS = [0.4, 0.3, 0.2, 0.1]; // distribution

    mouse = { x: -1000, y: -1000 };

    function weightedColor() {
      const r = Math.random();
      let cumulative = 0;
      for (let i = 0; i < COLOR_WEIGHTS.length; i++) {
        cumulative += COLOR_WEIGHTS[i];
        if (r <= cumulative) return COLORS[i];
      }
      return COLORS[0];
    }

    class Particle {
      constructor() {
        this.reset();
      }

      reset() {
        this.x = Math.random() * width;
        this.y = Math.random() * height;
        this.vx = (Math.random() - 0.5) * 0.4;
        this.vy = (Math.random() - 0.5) * 0.4;
        this.radius = Math.random() * 1.5 + 0.8;
        this.colorBase = weightedColor();
        this.opacity = Math.random() * 0.4 + 0.2;
        this.phaseX = Math.random() * Math.PI * 2;
        this.phaseY = Math.random() * Math.PI * 2;
        this.freqX = Math.random() * 0.002 + 0.001;
        this.freqY = Math.random() * 0.002 + 0.001;
      }

      update(time) {
        // Organic sine-wave drift
        this.x += this.vx + Math.sin(time * this.freqX + this.phaseX) * 0.15;
        this.y += this.vy + Math.cos(time * this.freqY + this.phaseY) * 0.15;

        // Mouse repulsion
        const dx = this.x - mouse.x;
        const dy = this.y - mouse.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < 120) {
          const force = (120 - dist) / 120 * 0.8;
          this.x += (dx / dist) * force;
          this.y += (dy / dist) * force;
        }

        // Wrap around edges
        if (this.x < -10) this.x = width + 10;
        if (this.x > width + 10) this.x = -10;
        if (this.y < -10) this.y = height + 10;
        if (this.y > height + 10) this.y = -10;
      }

      draw() {
        ctx.beginPath();
        ctx.arc(this.x, this.y, this.radius, 0, Math.PI * 2);
        ctx.fillStyle = this.colorBase + this.opacity + ')';
        ctx.fill();
      }
    }

    function initParticles() {
      width = canvas.width = canvas.offsetWidth;
      height = canvas.height = canvas.offsetHeight;
      const count = width < 640 ? 35 : width < 1024 ? 55 : 80;
      particles = [];
      for (let i = 0; i < count; i++) {
        particles.push(new Particle());
      }
    }

    function drawConnections() {
      const maxDist = 130;
      for (let i = 0; i < particles.length; i++) {
        for (let j = i + 1; j < particles.length; j++) {
          const dx = particles[i].x - particles[j].x;
          const dy = particles[i].y - particles[j].y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          if (dist < maxDist) {
            const alpha = (1 - dist / maxDist) * 0.12;
            ctx.beginPath();
            ctx.moveTo(particles[i].x, particles[i].y);
            ctx.lineTo(particles[j].x, particles[j].y);
            ctx.strokeStyle = `rgba(0, 245, 255, ${alpha})`;
            ctx.lineWidth = 0.5;
            ctx.stroke();
          }
        }
      }
    }

    function animate(time) {
      ctx.clearRect(0, 0, width, height);
      particles.forEach(p => {
        p.update(time);
        p.draw();
      });
      drawConnections();
      animationId = requestAnimationFrame(animate);
    }

    // Mouse tracking for particle repulsion
    document.addEventListener('mousemove', (e) => {
      const rect = canvas.getBoundingClientRect();
      mouse.x = e.clientX - rect.left;
      mouse.y = e.clientY - rect.top;
    });

    document.addEventListener('mouseleave', () => {
      mouse.x = -1000;
      mouse.y = -1000;
    });

    // Handle resize
    let resizeTimeout;
    window.addEventListener('resize', () => {
      clearTimeout(resizeTimeout);
      resizeTimeout = setTimeout(() => {
        cancelAnimationFrame(animationId);
        initParticles();
        animate(0);
      }, 200);
    });

    initParticles();
    animate(0);
  }


  /* ═══════════════════════════════════════════
     2. 3D CARD MOUSE TRACKING
     Tilts the hero credit card based on mouse
     position relative to card center. Adds a
     moving shine overlay for holographic effect.
     ═══════════════════════════════════════════ */
  const card3d = document.getElementById('card3d');
  const cardShine = document.getElementById('cardShine');

  if (card3d && !prefersReducedMotion) {
    const MAX_TILT = 15; // degrees

    card3d.addEventListener('mousemove', (e) => {
      const rect = card3d.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      const centerX = rect.width / 2;
      const centerY = rect.height / 2;

      const rotateY = ((x - centerX) / centerX) * MAX_TILT;
      const rotateX = ((centerY - y) / centerY) * MAX_TILT;

      card3d.style.transform = `rotateX(${rotateX}deg) rotateY(${rotateY}deg)`;

      // Move shine
      if (cardShine) {
        const shineX = (x / rect.width) * 100;
        const shineY = (y / rect.height) * 100;
        cardShine.style.background = `radial-gradient(circle at ${shineX}% ${shineY}%, rgba(255,255,255,0.2) 0%, transparent 60%)`;
      }
    });

    card3d.addEventListener('mouseleave', () => {
      card3d.style.transform = 'rotateX(0deg) rotateY(0deg)';
      card3d.style.transition = 'transform 0.6s cubic-bezier(0.22, 1, 0.36, 1)';
      setTimeout(() => {
        card3d.style.transition = 'transform 0.15s ease-out';
      }, 600);
    });

    card3d.addEventListener('mouseenter', () => {
      card3d.style.transition = 'transform 0.15s ease-out';
    });

    // Idle floating animation on mobile / when not hovered
    if (window.innerWidth <= 1024) {
      card3d.style.animation = 'float 6s ease-in-out infinite';
    }
  }


  /* ═══════════════════════════════════════════
     3. MAGNETIC CURSOR EFFECT
     Buttons with class "magnetic" subtly pull
     toward the mouse when nearby, creating a
     sense of interactive "intelligence."
     ═══════════════════════════════════════════ */
  if (!prefersReducedMotion) {
    const magneticElements = document.querySelectorAll('.magnetic');
    const MAGNETIC_STRENGTH = 0.3;
    const MAGNETIC_RADIUS = 80;

    magneticElements.forEach(el => {
      el.addEventListener('mousemove', (e) => {
        const rect = el.getBoundingClientRect();
        const x = e.clientX - rect.left - rect.width / 2;
        const y = e.clientY - rect.top - rect.height / 2;
        const dist = Math.sqrt(x * x + y * y);

        if (dist < MAGNETIC_RADIUS) {
          el.style.transform = `translate(${x * MAGNETIC_STRENGTH}px, ${y * MAGNETIC_STRENGTH}px)`;
        }
      });

      el.addEventListener('mouseleave', () => {
        el.style.transform = 'translate(0, 0)';
        el.style.transition = 'transform 0.4s cubic-bezier(0.22, 1, 0.36, 1)';
        setTimeout(() => {
          el.style.transition = '';
        }, 400);
      });
    });
  }


  /* ═══════════════════════════════════════════
     4. SCROLL OBSERVER FALLBACK
     For browsers without native scroll-driven
     animations (animation-timeline: view()).
     Uses IntersectionObserver to add .in-view.
     ═══════════════════════════════════════════ */
  const supportsScrollTimeline = CSS.supports('animation-timeline', 'view()');

  if (!supportsScrollTimeline && !prefersReducedMotion) {
    const revealElements = document.querySelectorAll('.reveal, .reveal-scale');
    const staggerContainers = document.querySelectorAll('.reveal-stagger');

    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('in-view');
          observer.unobserve(entry.target);
        }
      });
    }, {
      threshold: 0.15,
      rootMargin: '0px 0px -50px 0px'
    });

    revealElements.forEach(el => observer.observe(el));

    // For stagger containers, observe children
    staggerContainers.forEach(container => {
      const children = container.children;
      const childObserver = new IntersectionObserver((entries) => {
        entries.forEach((entry, i) => {
          if (entry.isIntersecting) {
            setTimeout(() => {
              entry.target.classList.add('in-view');
            }, i * 100);
            childObserver.unobserve(entry.target);
          }
        });
      }, {
        threshold: 0.1,
        rootMargin: '0px 0px -30px 0px'
      });

      Array.from(children).forEach(child => childObserver.observe(child));
    });
  }

  // If reduced motion, make everything visible immediately
  if (prefersReducedMotion) {
    document.querySelectorAll('.reveal, .reveal-scale, .reveal-stagger > *').forEach(el => {
      el.classList.add('in-view');
      el.style.opacity = '1';
      el.style.transform = 'none';
    });
  }


  /* ═══════════════════════════════════════════
     5. ANIMATED COUNTERS
     Elements with data-count attribute count
     up from 0 to target when scrolled into view.
     Uses easeOutExpo for natural deceleration.
     ═══════════════════════════════════════════ */
  const counters = document.querySelectorAll('[data-count]');
  const countedSet = new Set();

  function easeOutExpo(t) {
    return t === 1 ? 1 : 1 - Math.pow(2, -10 * t);
  }

  function animateCounter(el) {
    if (countedSet.has(el)) return;
    countedSet.add(el);

    const target = parseInt(el.dataset.count, 10);
    const duration = parseInt(el.dataset.duration, 10) || 2000;
    const prefix = el.dataset.prefix || '';
    const start = performance.now();

    function tick(now) {
      const elapsed = now - start;
      const progress = Math.min(elapsed / duration, 1);
      const value = Math.round(easeOutExpo(progress) * target);

      // Check if parent has the formatting
      if (el.tagName === 'SPAN') {
        el.textContent = value.toLocaleString('en-IN');
      } else {
        const suffix = el.textContent.includes('%') ? '%' : el.textContent.includes('+') ? '+' : '';
        el.textContent = (prefix ? '' : '') + value.toLocaleString('en-IN') + suffix;
      }

      if (progress < 1) {
        requestAnimationFrame(tick);
      }
    }

    requestAnimationFrame(tick);
  }

  if (counters.length) {
    const counterObserver = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          animateCounter(entry.target);
          counterObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.3 });

    counters.forEach(el => counterObserver.observe(el));
  }


  /* ═══════════════════════════════════════════
     6. TERMINAL TYPING ANIMATION
     Lines appear sequentially with staggered
     delays, simulating a real CLI pipeline.
     ═══════════════════════════════════════════ */
  const terminalBody = document.getElementById('terminalBody');

  if (terminalBody) {
    let terminalAnimated = false;

    const terminalObserver = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting && !terminalAnimated) {
          terminalAnimated = true;
          const lines = terminalBody.querySelectorAll('.terminal-line');
          lines.forEach(line => {
            const delay = parseInt(line.dataset.delay, 10) || 0;
            setTimeout(() => {
              line.classList.add('visible');
            }, delay);
          });
          terminalObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.3 });

    terminalObserver.observe(terminalBody);
  }


  /* ═══════════════════════════════════════════
     7. NAVIGATION SCROLL STATE
     Adds .scrolled to nav when page is scrolled
     past hero, triggering glass background.
     ═══════════════════════════════════════════ */
  const nav = document.getElementById('nav');

  if (nav) {
    let lastScroll = 0;
    const scrollThreshold = 60;

    window.addEventListener('scroll', () => {
      const currentScroll = window.scrollY;

      if (currentScroll > scrollThreshold) {
        nav.classList.add('scrolled');
      } else {
        nav.classList.remove('scrolled');
      }

      lastScroll = currentScroll;
    }, { passive: true });
  }


  /* ═══════════════════════════════════════════
     8. SMOOTH SCROLL + MOBILE MENU
     ═══════════════════════════════════════════ */
  // Smooth scroll for anchor links
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', (e) => {
      const targetId = anchor.getAttribute('href');
      if (targetId === '#') return;

      const target = document.querySelector(targetId);
      if (target) {
        e.preventDefault();
        const navHeight = nav ? nav.offsetHeight : 0;
        const targetPosition = target.getBoundingClientRect().top + window.scrollY - navHeight - 20;

        window.scrollTo({
          top: targetPosition,
          behavior: 'smooth'
        });

        // Close mobile menu if open
        const navLinks = document.getElementById('navLinks');
        if (navLinks) navLinks.classList.remove('open');
      }
    });
  });

  // Mobile menu toggle
  const navToggle = document.getElementById('navToggle');
  const navLinks = document.getElementById('navLinks');

  if (navToggle && navLinks) {
    navToggle.addEventListener('click', () => {
      navLinks.classList.toggle('open');
      // Simple mobile menu slide-down
      if (navLinks.classList.contains('open')) {
        navLinks.style.display = 'flex';
        navLinks.style.flexDirection = 'column';
        navLinks.style.position = 'absolute';
        navLinks.style.top = '100%';
        navLinks.style.left = '0';
        navLinks.style.right = '0';
        navLinks.style.background = 'rgba(2, 8, 16, 0.95)';
        navLinks.style.backdropFilter = 'blur(20px)';
        navLinks.style.padding = '24px';
        navLinks.style.borderBottom = '1px solid rgba(255,255,255,0.08)';
        navLinks.style.gap = '16px';
        navLinks.style.animation = 'fade-in-up 0.3s ease both';
      } else {
        navLinks.style = '';
      }
    });
  }

})();
