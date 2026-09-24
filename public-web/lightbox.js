// Click any screenshot to see it at full size. Built on <dialog> rather than
// a hand-rolled overlay: showModal() gives focus trapping and Escape-to-close
// for free, and the ::backdrop pseudo-element covers the dimmed background —
// this file only wires up what <dialog> doesn't do on its own.
(function () {
  const dialog = document.getElementById('lightbox');
  const img = document.getElementById('lightbox-img');
  const closeButton = document.getElementById('lightbox-close');
  if (!dialog || !img || !closeButton) return;

  // Gallery thumbnails carry the full-size file in data-full: the page stays
  // light, and the dialog still shows the real screenshot.
  function open(shot) {
    img.src = shot.dataset.full || shot.currentSrc || shot.src;
    img.alt = shot.alt;
    dialog.showModal();
  }

  document.querySelectorAll('.device__shot').forEach((shot) => {
    shot.addEventListener('click', () => open(shot));
  });

  closeButton.addEventListener('click', () => dialog.close());

  // A click that lands on the dialog's own backdrop area (not on the image
  // or the close button) should close it too, same as tapping outside a
  // sheet on the phone this is meant to evoke.
  dialog.addEventListener('click', (event) => {
    if (event.target === dialog) dialog.close();
  });

  // The image itself is also a close target, matching the zoom-out cursor.
  img.addEventListener('click', () => dialog.close());

  dialog.addEventListener('close', () => { img.src = ''; });
})();
