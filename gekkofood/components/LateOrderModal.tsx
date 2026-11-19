"use client";

/** Aviso que hay que aceptar antes de pedir cuando el pedido ya no sale hoy. */
export default function LateOrderModal({
  title,
  body,
  onAccept,
  onCancel,
}: {
  title: string;
  body: string;
  onAccept: () => void;
  onCancel: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/65 p-4 sm:items-center" role="presentation">
      <div
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="late-title"
        aria-describedby="late-body"
        className="anim-modal card w-full max-w-sm p-6 text-center"
      >
        <p className="text-4xl" aria-hidden>
          🕐
        </p>
        <h2 id="late-title" className="mt-2 text-xl font-extrabold">
          {title}
        </h2>
        <p id="late-body" className="mt-2 text-sm text-ink/75">
          {body}
        </p>
        <button type="button" className="btn btn-gold mt-5 w-full" onClick={onAccept} autoFocus>
          Aceptar y separar mi pedido
        </button>
        <button type="button" className="btn btn-light mt-2 w-full" onClick={onCancel}>
          Cancelar
        </button>
      </div>
    </div>
  );
}
