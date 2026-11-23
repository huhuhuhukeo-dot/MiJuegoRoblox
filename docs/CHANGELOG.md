# Registro de cambios

## V1 — Prototipo jugable (rama `claude/zealous-cerf-d1pt3e`)

Punto de partida: el repositorio solo contenía un `README.md` vacío; no había código, Rojo
ni lugar de Studio. Todo se construyó desde cero.

### Base técnica
- Layout Rojo (`default.project.json`): `Shared` / `Server` / `Client`, propiedades de
  `StarterPlayer` (1ª persona bloqueada, salto por altura) y `Workspace.StreamingEnabled = false`.
- Configuración centralizada (`GameConfig`, `Controls`), contrato de datos (`Contract`),
  remotos declarados en un único módulo, utilidades (`Signal`, `Maid`, `RateLimiter`, `Validate`).

### Etapa 1 — Cámara en primera persona
- `CameraController`: `LockFirstPerson` + zoom bloqueado forzado cada frame, re-enlace al
  reaparecer, cuerpo/accesorios ocultos localmente, anti-clip por spherecast, FOV suave.
- Orden de render documentado para que la mano/visual lean la cámara final.

### Etapa 2 — Movimiento
- `MovementController` (cliente) + `MovementService` (servidor) + `CrouchPose` (compartido).
- Correr con transición suave, agacharse R15 real (HipHeight + flexión de piernas, colisión
  más baja), comprobación de techo en cliente y servidor, salto con cooldown, penalización por
  carga, anti-speed en servidor, ganchos para estamina/sonido.

### Etapa 3 — Mano física
- `HandService`: pieza física por personaje con AlignPosition/AlignOrientation, propiedad
  del jugador, validación de alcance y recuperación en servidor.
- `HandController`: reposo / extendida (clic derecho), alcance con rueda/Z-X, límite físico de
  alcance, recuperación si se atasca.
- `ArmRig`/`ArmRenderer`: un único brazo visual con IK de dos huesos (local y remotos).

### Etapa 4 — Agarrar, levantar, arrastrar, soltar
- `GrabService`: validación completa, modos Lift/Drag/Articulated, propiedad de red segura,
  grupos de colisión, restauración al soltar, validación anti-exploit periódica,
  liberación por muerte/salida.
- `GrabController`: mantener para sostener, auto-soltar si el objeto se bloquea, estado
  derivado del servidor.
- `RecoveryService`: recuperación de objetos caídos y reinicio desde plantillas.
- Objetos de prueba: caja liviana, caja pesada, bolsa, lata, caja pequeña, mesas.

### Etapa 5 — Interacciones
- `InteractionService` con contrato común y validación centralizada.
- Módulos: `Door`, `Drawer` (sobre `ArticulatedJoint`), `Switch`, `Button`, `Collectible`,
  `Container`, `MoneyBag`; `DeliveryService`, `LootService`, `WorldStateService`.
- Escenario: habitación, bóveda bloqueada, interruptor de energía, zona de entrega, botón de reinicio.

### Etapa 6 — Multijugador
- Todo el estado compartido vive en el servidor (atributos replicados); rate limit en todos
  los remotos; propiedad única de objetos; manos remotas visibles y coherentes.

## Limitaciones conocidas / pendientes
- **No probado en Studio** (ver `docs/TESTING.md`); los valores de fuerza/respuesta son
  estimaciones razonadas que probablemente necesiten ajuste fino tras jugar.
- El agarre se ejecuta con la propiedad de red del portador: un exploiter podría mover el
  objeto que sostiene dentro de los márgenes de validación (distancia 16, velocidad 90).
- Mientras se sostiene, un objeto no colisiona con ningún personaje (los demás jugadores lo
  atraviesan). Es intencional para evitar empujones y "subirse a la caja", pero es visible.
- Agachado completo solo con R15; en R6 solo baja la cámara.
- El túnel está medido para la escala de avatar estándar.
- Sin animaciones de mano importadas: la pose de agarre es procedural (`grip` en `ArmRig`).
- Rotar el objeto sostenido y lanzar con fuerza no están implementados (no se pidieron).
