# Gekko (antes GoldenTicket) — contexto del proyecto

App web de **Gekko**: tienda de **pollo aderezado** (piezas y promos, se entrega los domingos) y **belleza**, más un apartado de **sorteos/rifas**. Los usuarios se registran con celular y contraseña, hacen pedidos o reservan números, pagan por Yape y envían la captura por WhatsApp. El admin confirma los pagos a mano. Nombre anterior: GoldenTicket (el repo ya se llama gekko-portal-de-ventas).

- **Producción:** https://gekkoperu.vercel.app (antes goldenticketperu.vercel.app, que redirige al nuevo).
- **Repo:** github.com/JeanPaul0509/gekko-portal-de-ventas (rama `main`; antes se llamaba App-sorteos). El código está en `app-sorteos/` (Gekko) y `gekkofood/` (Gekko Food, ver más abajo).
- **Stack:** Next.js 15 (App Router) + React 19 + Tailwind v4 + Supabase (Auth, Postgres, Storage) + Vercel.
- **Idioma:** todo en español de Perú. El usuario no es programador: explicar en pasos simples.

## Cómo se trabaja (flujo de actualización)

1. Claude edita el código en el repo y hace `git push` a `main`. **Vercel publica solo** en 1-2 minutos.
2. Si el cambio toca la base de datos: crear `app-sorteos/supabase/migrations/00N_nombre.sql`, agregar lo mismo al final de `supabase/schema.sql` y **darle al usuario el SQL para que lo pegue en Supabase → SQL Editor → Run**. Claude no tiene acceso directo a Supabase.
3. El entorno de Claude no puede hacer `npm install` (registro bloqueado), así que no puede compilar. Hacer revisión de sintaxis con cuidado y pedir al usuario la captura del log de Vercel si el deploy falla.
4. Variables de entorno en Vercel (Settings → Environment Variables, tipo Config): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` (publishable key), `NEXT_PUBLIC_YAPE_NUMBER`, `NEXT_PUBLIC_YAPE_NAME`. Para la verificación de celular (ver más abajo): `NEXT_PUBLIC_VERIFY_WHATSAPP_NUMBER` (51 + número del chip de verificación) y tres **secretas, marcadas Sensitive y SIN `NEXT_PUBLIC`**: `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_APP_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`. Después de cambiarlas: Deployments → ⋯ → Redeploy.

## Reglas del código

- **Antes de tocar cualquier pantalla, leer `app-sorteos/DESIGN.md`** (paleta Carbón y champán, tarjetas marfil, boletos solo en sorteos, tipografía Archivo, movimiento según Emil Kowalski). Si un cambio no encaja, actualizar primero DESIGN.md.
- Montos, conteos y plurales: `money()`, `num()`, `plural()`, `soldPercent()` de `lib/utils.ts`.
- Imágenes de premios: `components/SafeImg.tsx`, nunca `<img>` directo.
- Textos largos: `[overflow-wrap:anywhere]`; probar a 360px de ancho sin scroll horizontal.
- Toda escritura sensible pasa por funciones SQL `security definer` que verifican `is_admin()`; RLS activo en todas las tablas.

## Autenticación

- Los campos de contraseña (login y registro, en las dos páginas) usan `components/PasswordInput.tsx`, con ojito para mostrar/ocultar. Hay una copia en `app-sorteos/` y otra en `gekkofood/`.
- Login con celular + contraseña. Internamente cada celular es un correo `9XXXXXXXX@celular.sorteos.app` (sin el 51). En Supabase, "Confirm email" está **desactivado**.
- El registro solo crea usuarios comunes. Admin: crear usuario en Supabase (Auth → Add user, Auto Confirm) y luego `update public.profiles set role = 'admin' where phone = '9XXXXXXXX';`.
- Admin actual: celular `994722642`.

## Tienda (migración 009)

- **Productos** (`products`): nombre, descripción, categoría (`pollo` / `promos` / `belleza`), precio, **unidades (stock)**, foto, visible/oculto. Los crea el admin en **Admin → Productos** (foto subida al bucket `raffle-images`, carpeta `productos/`, comprimida en el navegador). Semilla con los 9 productos del flyer (stock 0 hasta que el admin ponga las unidades y fotos).
- **Pedidos** (`orders` + `order_items`, con nombre y precio guardados al momento): estados `pending` (esperando pago) → `paid` → `delivered`, o `cancelled`. Todo pasa por funciones SQL `security definer`: `create_order` (revisa y descuenta stock, máx. 3 pedidos en espera por persona), `cancel_my_order` y `admin_set_order_status` (cancelar devuelve el stock). Nadie escribe directo en las tablas.
- **Cliente:** `/tienda` (catálogo con filtros y barra del carrito), `/carrito` (datos de entrega, Yape, "Ir a pagar" abre WhatsApp con el pedido), `/mis-pedidos` (estado, reenviar captura, cancelar). El carrito vive en `localStorage` (`CartProvider`).
- **Admin:** pestañas Pedidos (por cobrar / por entregar / entregados / cancelados + resumen de lo que hay que preparar), Productos, Sorteos (lo de siempre) y Ajustes (redes, restablecer contraseña, términos).
- Reglas del negocio: se pide durante la semana y **se entrega los domingos** (`DELIVERY_NOTE` en `lib/store.ts`). Las promos tienen su propio stock (no descuentan de las piezas).
- **Oferta de los jueves (migración 010, hora de Lima):** solo piezas de `pollo`; por cuenta y por pieza, solo la 1.ª unidad del día a S/5 y desde la 2.ª precio normal (migración 011 corrige la 010) (cuenta lo ya pedido ese jueves, sin cancelados). El precio lo calcula `create_order` (parte el ítem en tramos con el mismo nombre); `promo_info()` le da al carrito lo ya pedido hoy; `priceTiers()` en `lib/store.ts` es el espejo para mostrar. Las promos no entran.
- Sin tienda sin login: todo requiere cuenta (igual que los sorteos). Idea pendiente: dejar ver el catálogo sin registrarse.
- **WhatsApp de pedidos y capturas (tienda y sorteos): 912389459**, fijo en el código como `WHATSAPP_NUMBER` en `lib/utils.ts` (ya no es variable de Vercel). El 994722642 es solo el celular del admin para entrar a la app.

## Funciones ya hechas (sorteos)

- Registro/login por celular; sorteos con foto, ícono, especificaciones, precio, cantidad de tickets (1–10,000) y fecha opcional.
- Tablero de números de 100 en 100 (‹ N ›): verde disponible, amarillo reservado, gris vendido. Máximo 5 por compra **y máximo 5 en espera por persona por sorteo** hasta que el admin confirme.
- Compra: pide nombre, reserva y abre WhatsApp (api.whatsapp.com, conserva emojis) con mensaje automático y "Adjunto captura de Yape".
- Mis números: foto del premio, estado, reenviar WhatsApp, botón al grupo de WhatsApp (solo con pago confirmado), aviso "¡Ganaste!".
- Admin: crear sorteo; finalizar/eliminar con confirmación escribiendo FINALIZAR/ELIMINAR; pagos por confirmar agrupados por persona + botón "Avisarle por WhatsApp"; tablero con cambio de estado; buscador del número ganador con llamar/WhatsApp; **publicar ganador** (solo números pagados, nombre abreviado "Juan P.", link de video); lista de compradores paginada + exportar a Excel (CSV protegido contra fórmulas); enlace de grupo de WhatsApp por sorteo; redes sociales (WhatsApp, Instagram, TikTok); **restablecer contraseña** de un usuario; **editor de Términos y condiciones**.
- Página pública `/privacidad` (texto fijo en `app/privacidad/page.tsx`; la pide Meta para publicar la app; borrador que debe revisar un abogado antes de cobrar). Página pública `/terminos` (plantilla en `lib/terms.ts`, editable desde el admin). Reglas acordadas: el sorteo se hace cuando se venden todos los números; se contacta al ganador durante 7 días, si no responde se vuelve a sortear sin ese número; la entrega se coordina por WhatsApp.
- Tarjetas con % vendido honesto y conteo de personas; ganador visible en la tarjeta y en el detalle.
- Diseño: boleto dorado animado en el inicio y en el login, ícono propio: monograma G (`app/icon.svg`, `app/apple-icon.png`), animaciones cortas, esqueletos de carga, casos extremos probados con break-ui.

## Verificación de celular por WhatsApp (código listo; falta conectar Meta)

- **Cómo funciona (verificación inversa, gratis):** al comprar, la persona toca "Verificar celular" → se le da un código `GT-XXXXXX` (vale 15 min) y se abre WhatsApp hacia el chip de verificación con el mensaje escrito → al enviarlo, Meta avisa a `app/api/whatsapp/route.ts` → la función SQL `confirm_phone_verification` compara el celular que envió con el de la cuenta y el código, y marca `profiles.verified_at`. La ventana (`components/VerifyPhoneModal.tsx`) revisa cada 3 s y sigue sola con la compra. La app **no responde nada por WhatsApp**: solo recibe mensajes (gratis); enviar respuestas sí se cobra desde el 1-oct-2026.
- **Chip de verificación:** 913880121 (aparte del número que recibe las capturas de pago, `WHATSAPP_NUMBER`). Debe registrarse en la API de Meta, por lo que pierde el WhatsApp normal; no afecta Yape.
- **Interruptor:** viene **apagado** (`site_settings.require_phone_verification = false`) para que nadie se quede sin comprar mientras Meta no esté conectado. Encender: `update public.site_settings set require_phone_verification = true where id = 1;` (apagar con `false`). El admin no necesita verificarse. Al encenderlo, los usuarios ya registrados deberán verificarse la próxima vez que compren.
- **Webhook en Meta:** URL `https://gekkoperu.vercel.app/api/whatsapp`, token = `WHATSAPP_VERIFY_TOKEN`, suscribir el campo `messages`. La ruta está abierta en `middleware.ts` (`OPEN_ROUTES`) y valida la firma `X-Hub-Signature-256` con `WHATSAPP_APP_SECRET`.
- **Ojo, modo Live:** en modo desarrollo Meta puede no enviar los mensajes de personas reales al webhook; hay que **publicar la app (Live)**, y para eso pide URL de privacidad (`https://gekkoperu.vercel.app/privacidad`). Posible que también pida verificación del negocio con documentos: avisar al usuario antes de subir nada. **No registrar el chip 913880121 en la API hasta confirmar que se puede publicar la app** (ese paso le quita el WhatsApp normal). App de Meta creada: "GoldenTicket Verificación".
- **Pendiente de conectar (lo hace el usuario en Meta):** cuenta de desarrollador, app con producto WhatsApp, registrar el chip, webhook y variables en Vercel. Luego probar con un celular y recién encender el interruptor.

## Migraciones SQL (`supabase/migrations/`)

002 grupo WhatsApp · 003 límite de 5 en espera · 004 conteo de compradores · 005 redes sociales · 006 límites de texto · 007 ganador + reset de contraseña + términos · 008 verificación de celular (columna `verified_at`, interruptor, códigos, `reserve_tickets` con la revisión) · 009 tienda (productos, pedidos, stock) · 010 oferta de los jueves · 011 jueves: solo la 1.ª a S/5 · 012 Gekko Food (carta, pedidos, cartilla) · 013 fotos de Gekko Food · 014 acompañamiento (papa y arroz / solo arroz). El usuario las corre a mano; si algo falla por "función no existe", confirmar que corrió la migración correspondiente.

## Gekko Food (carpeta `gekkofood/`, migración 012)

- **Qué es:** segunda página, aparte de Gekko, para vender **pollo broaster**: pecho S/15, pierna S/13, entrepierna S/13, ala S/11 (editables en Admin → Menú). Cada pieza se pide con **papa y arroz** (viene marcada) o **solo arroz** (`side` = `papa_arroz` / `arroz`; `papa` queda solo para pedidos antiguos; migración 014). Mismo repo, carpeta `gekkofood/` (Next.js 15, mismo stack y mismo diseño que `app-sorteos/`; leer `app-sorteos/DESIGN.md`).
- **Cuentas compartidas:** usa el **mismo proyecto de Supabase** (mismas variables `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_ANON_KEY`), así que el celular y la contraseña de Gekko sirven en Gekko Food. La sesión no se comparte entre dominios: la persona entra una vez en cada página. El admin es el mismo (`profiles.role = 'admin'`).
- **Vercel:** proyecto **aparte**, con *Root Directory* = `gekkofood`. Variables: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_YAPE_NUMBER`, `NEXT_PUBLIC_YAPE_NAME` (las mismas de Gekko). No necesita las de WhatsApp/Meta.
- **SQL:** `app-sorteos/supabase/migrations/012_gekkofood.sql` (y al final de `schema.sql`; las migraciones de las dos páginas viven juntas porque la base es una sola). Tablas `food_items`, `food_orders`, `food_order_items`; funciones `food_card`, `create_food_order`, `create_food_reward`, `cancel_my_food_order`, `admin_set_food_order_status`.
- **Cartilla:** cada pedido **pagado/entregado** (no regalo) suma 1 punto; con 7, el siguiente pedido es un **regalo** (pieza de broaster con chaufa a elección, o hamburguesa), total S/0, entra como "pagado" y **no suma punto**; después la cartilla vuelve a empezar. Los puntos se **calculan** (`food_points`) a partir de los pedidos: si se cancela un pedido o un regalo, la cartilla se corrige sola. Si alguien junta más de 7 antes de canjear, el excedente se conserva.
- **Fotos del menú (migración 013):** `food_items.image_url`; el admin las sube en **Admin → Menú** (se comprimen en el navegador y van al bucket `raffle-images`, carpeta `comida/`). Sin foto se ve el ícono 🍗. Hay que correr la 013 **antes** de desplegar el código que la usa, o el menú no carga.
- **"Ir a pagar" abre WhatsApp al instante:** `CartView` y `RewardForm` abren una pestaña con el toque del botón (`window.open("about:blank")`) y, cuando el pedido se guarda, la mandan a WhatsApp con el pedido escrito; si el navegador no deja abrir pestañas, navega la misma. Si el pedido falla, se cierra la pestaña.
- **Pantallas:** `/menu`, `/carrito` ("Ir a pagar" abre WhatsApp con el pedido), `/cartilla` (bolitas + canje del regalo), `/mis-pedidos`, `/admin/pedidos` (por cobrar / por entregar / entregados / cancelados + resumen "para preparar"), `/admin/menu` (precio, nombre, visible/agotado).
- **WhatsApp y Yape:** igual que Gekko, **912389459** (`WHATSAPP_NUMBER` en `gekkofood/lib/utils.ts`).
- **Entrega (decidido por el usuario):** se puede pedir **hasta las 10 a. m.** y la entrega es **de 12:30 a 2 p. m. en la Universidad ESAN**. **Días de reparto: lunes, martes, miércoles, viernes y sábado (jueves y domingo no hay atención).** Pasadas las 10 a. m. (o en un día sin atención) **igual se puede reservar**, pero la página avisa con un recuadro destacado que ya no sale hoy y cuándo sale (y el mensaje de WhatsApp dice "Para: mañana/el viernes") ("mañana", "el viernes", "el lunes"; `nextDelivery()`/`deliveryLine()` en `gekkofood/lib/food.ts`, hora de Lima; es solo un aviso, la base no bloquea pedidos). El campo de dirección pide "¿Dónde te encontramos en ESAN?". Pendiente: confirmar si se debe bloquear el pedido pasada la hora o en días sin atención; fotos de las piezas; precio de hamburguesa/chaufa extra si se venden aparte.

## Pendientes / ideas

- **Decisión del usuario:** el negocio pasa a llamarse **Gekko**. Pausar el registro del chip 913880121 en Meta (el WABA se iba a llamar "GoldenTicket" y los sorteos cuentan como "juego con dinero" para WhatsApp). Plan: verificación manual desde el admin (`admin_verify_phone`) como respaldo.
- Los términos guardados en la base pueden seguir diciendo GoldenTicket (Admin → Ajustes → Términos).
- Aspectos legales de la tienda a consultar: libro de reclamaciones (Indecopi) y permisos sanitarios/municipales para vender alimentos.

- **Antes de encender la verificación:** WhatsApp está lanzando nombres de usuario; si alguien lo activa, Meta puede mandar al webhook un identificador (BSUID) en vez de su celular (`from`/`wa_id`) y `route.ts` lo descarta (no verifica). Falta una salida: mensaje en `VerifyPhoneModal` para esos casos + botón/función SQL de admin para verificar un celular a mano (`admin_verify_phone`).
- Terminar de conectar la verificación de celular con Meta (ver sección arriba) y encender el interruptor. Idea: botón en el admin para encender/apagar la regla sin SQL, e insignia ✅ de verificado en la lista de compradores.
- Historial de sorteos pasados con ganadores en el inicio.
- Sorteo al azar dentro de la app para el en vivo.
- Antes de cobrar: consultar con abogado/ONAGI el permiso para rifas y revisar los términos.
- Por uso comercial: Vercel Pro y Supabase Pro (el plan gratis de Supabase se pausa tras ~7 días sin actividad).
