# Arquitectura

## Estructura

```
default.project.json          Mapa Rojo -> DataModel
src/
  shared/   -> ReplicatedStorage.Shared        (cliente + servidor)
    Config/       GameConfig (valores), Controls (teclas)
    Interaction/  Contract (tags/atributos/nombres), Targeting (búsquedas puras)
    Movement/     CrouchPose (pose de agachado, usada por ambos lados)
    Net/          Remotes (declaración única de remotos), Validate (guardas de tipos)
    Physics/      GrabMath (matemática pura: clasificación, fuerzas, IK, piernas)
    Util/         Signal, Maid, RateLimiter
  server/   -> ServerScriptService.Server      (Script + módulos)
    init.server.lua   arranque en orden de dependencias
    Services/         CharacterService, CollisionService, HandService, GrabService,
                      MovementService, InteractionService, DeliveryService,
                      LootService, RecoveryService, WorldStateService
    Interactions/     Door, Drawer, Switch, Button, Collectible, Container, MoneyBag
                      (+ ArticulatedJoint: helper compartido de puertas/cajones)
    World/            TestArenaBuilder (escenario de pruebas por código)
  client/   -> StarterPlayerScripts.Client     (LocalScript + módulos)
    init.client.lua   arranque
    Controllers/      PlayerContext, InputBinder, CameraController, MovementController,
                      TargetingController, HandController, GrabController,
                      InteractionController, HUDController
    Visual/           ArmRig (brazo cosmético con IK), ArmRenderer (mano local y remotas)
tests/pure_logic.spec.lua      pruebas de la lógica pura
```

Un solo `Script` en el servidor y un solo `LocalScript` en el cliente; todo lo demás son
`ModuleScript` con `Init()`. No hay scripts por objeto.

## Principios

* **Servidor autoritativo**: el cliente pide, el servidor valida y decide. El cliente refleja
  el estado replicado (atributos, `ObjectValue HeldObject`), así se corrige solo.
* **Física con constraints, no teletransportes**: la mano y los objetos se mueven con
  `AlignPosition`/`AlignOrientation` de fuerza finita; chocan con el mundo en vez de
  atravesarlo. Solo se teletransporta en recuperaciones (mano atascada, objeto caído,
  rebobinado anti-exploit).
* **Visual separado de la lógica**: la mano física (`PhysicsHand`, invisible) hace el
  trabajo; el brazo visible (`ArmRig`) se dibuja localmente encima con IK y nunca colisiona
  ni bloquea rayos.
* **Datos, no scripts**: un objeto es interactivo por tags y atributos (`Contract.lua`).

## Mano física (Etapa 3)

* `HandService` (servidor) crea por personaje una pieza `PhysicsHand` (ensamblaje propio,
  grupo de colisión `Hand`) con `AlignPosition` y `AlignOrientation` en modo OneAttachment, y
  da la propiedad de red al jugador.
* `HandController` (cliente) calcula cada frame el objetivo (reposo / rayo del punto de mira a
  la distancia de alcance) limitado a `MaxReach` desde el hombro y lo escribe en los
  constraints. Como el cliente simula esa pieza, el movimiento resultante se replica a todos.
* El servidor comprueba la distancia mano–cabeza; si se sale del límite durante
  `ServerViolationTime`, suelta lo agarrado y recoloca la mano.

## Agarre (Etapa 4)

`GrabRequest` (RemoteFunction) → `GrabService.TryGrab` valida: tipo de argumentos, tag
`Grabbable`, no anclado, nadie lo sostiene, el jugador no sostiene nada, vivo, distancia
cabeza→punto ≤ `Grab.Range` + tolerancia, línea de visión, masa/tamaño (`GrabMath.classify`).

| Modo | Constraints | Comportamiento |
|---|---|---|
| Lift | AlignPosition (magnitud) + AlignOrientation | fuerza = masa·(g + aceleración decreciente con el peso): los pesados responden lento |
| Drag | AlignPosition **por eje**, fuerza vertical < peso | nunca se levanta, se arrastra venciendo la fricción |
| Articulated | AlignPosition | puertas/cajones: la bisagra/raíl sigue limitando el movimiento |

Durante el agarre el objeto pasa al grupo `Held` (no choca con personajes ni manos, sí con
paredes) y su propiedad de red pasa al jugador. Al soltar: se quitan los constraints, se
mantiene la velocidad, se restauran las colisiones cuando ningún personaje lo solapa y la
propiedad vuelve al servidor. Validación periódica: distancia al jugador, velocidad máxima,
rebobinado a la última posición válida.

Matriz de colisión: ver cabecera de `CollisionService.lua`.

## Interacciones (Etapa 5)

`InteractionService` carga todos los módulos de `Server/Interactions` y aplica a cada
instancia con tag `Interactable` el módulo indicado por su atributo `InteractionType`.
Contrato (documentado en `InteractionService.lua`):

```lua
{ Type, Range?, Cooldown?, Setup, Cleanup?, CanInteract?, Interact,
  OnGrabStarted?, OnGrabEnded?, OnReset? }
```

El servicio valida antes de llamar al módulo: rate limit, vivo, distancia al punto más
cercano, línea de visión, `InteractEnabled`, cooldown por instancia. Los textos que muestra el
cliente vienen del atributo `InteractPrompt` que escribe el servidor.

**Añadir una interacción nueva**: crear `Server/Interactions/MiTipo.lua` con `Type = "MiTipo"`
y poner `InteractionType = "MiTipo"` + tag `Interactable` en el objeto. Nada más.

## Red y seguridad (Etapa 6)

| Remoto | Dirección | Validación |
|---|---|---|
| GrabRequest | C→S | rate limit 5/s, tipos, todo lo de TryGrab |
| ReleaseRequest | C→S | rate limit; solo suelta lo propio |
| InteractRequest | C→S | rate limit 5/s, instancia registrada, distancia, visión, cooldown |
| MovementState | C→S | rate limit, booleanos; el servidor re-comprueba si se puede levantar |
| Notify | S→C | — |

* Ningún remoto acepta posiciones o fuerzas del cliente (el punto de agarre se recorta a la caja
  del objeto y se comprueba la distancia).
* Un objeto tiene como máximo un portador (`holdsByPart` + atributo `HeldBy`); el servidor es
  monohilo y `TryGrab` no cede, así que dos peticiones simultáneas no pueden ganar ambas.
* Muerte, reaparición y desconexión sueltan lo agarrado y devuelven el botín del bolsillo.
* `RecoveryService` devuelve objetos caídos y reinicia el escenario desde plantillas.
* `MovementService` mide desplazamiento horizontal (anti-speed) con tolerancia amplia.

## Trabajo en paralelo (Claude / Codex)

Cada sistema es un módulo con una única responsabilidad y una API pequeña, así que se pueden
repartir por carpeta sin pisarse:

* Movimiento/cámara: `client/Controllers/{Camera,Movement}Controller.lua`, `shared/Movement/`
* Mano y agarre: `server/Services/{Hand,Grab}Service.lua`, `client/Controllers/{Hand,Grab}Controller.lua`, `shared/Physics/`
* Interacciones: un archivo por tipo en `server/Interactions/`
* Visual: `client/Visual/`
* Contratos compartidos que conviene cambiar con cuidado (afectan a todos):
  `shared/Interaction/Contract.lua`, `shared/Net/Remotes.lua`, `shared/Config/*`.
