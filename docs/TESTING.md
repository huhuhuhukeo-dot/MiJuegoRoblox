# Pruebas

## Resumen honesto

El entorno donde se desarrolló este prototipo **no tiene Roblox Studio** (Linux, sin
interfaz gráfica), así que **ninguna prueba jugable se ha ejecutado todavía**. Lo que sí se
ejecutó:

| Verificación | Herramienta | Resultado |
|---|---|---|
| Sintaxis de los 44 archivos `.lua` (src + tests) | Compilador oficial de Luau (vía crate `mlua`, feature `luau`) | 44/44 compilan |
| Lint | Selene 0.31 con un std mínimo (Luau + globales Roblox)¹ | 0 errores, 0 avisos |
| Estructura del lugar | `rojo build default.project.json` (Rojo 7.7.1) | construye; árbol de instancias y propiedades de `StarterPlayer`/`Workspace` correctos |
| Lógica pura | `tests/pure_logic.spec.lua` en la VM de Luau | 44/44 |

¹ El std `roblox` completo de Selene necesita descargar el API dump de Roblox, bloqueado en el
entorno. En una máquina con red: `selene src` (usa `selene.toml` del repositorio).

Lo que **no** cubren estas comprobaciones: el comportamiento físico real (estabilidad de
constraints, fuerzas), la replicación, el comportamiento del módulo de cámara de Roblox y
cualquier error de API que solo aparece en ejecución. Todo eso debe verificarse en Studio con
la lista de abajo.

## Ejecutar las pruebas de lógica pura

Cualquier runtime de Luau que defina `requirePath(ruta)` (carga un archivo relativo a la raíz
del repositorio y devuelve su valor) puede ejecutar `tests/pure_logic.spec.lua`.
En Studio: pega el archivo en la barra de comandos sustituyendo `requirePath` por
`require(game.ReplicatedStorage.Shared.Physics.GrabMath)` etc.

## Pruebas manuales en Studio — un jugador

Marcar cada una al ejecutarla. Estado actual de todas: **PENDIENTE**.

### Etapa 1 — Cámara
- [ ] Al entrar, la cámara está en primera persona; la rueda no aleja la cámara.
- [ ] Ratón mueve la vista en horizontal y vertical sin vibraciones.
- [ ] No se ve el propio cuerpo ni accesorios (pelo, sombreros) delante de la cámara.
- [ ] Pegado a una pared, la cámara no la atraviesa.
- [ ] Morir y reaparecer: la cámara vuelve a primera persona y sigue al personaje nuevo.

### Etapa 2 — Movimiento
- [ ] WASD responde; el personaje mira donde mira la cámara.
- [ ] Shift: aceleración suave a correr y ligero aumento de FOV; al soltar vuelve a caminar.
- [ ] Ctrl/C: el cuerpo y la cámara bajan suavemente; se puede andar agachado.
- [ ] Entrar agachado al túnel y soltar Ctrl: **no** se levanta hasta salir del túnel.
- [ ] Espacio: salto controlado; no se puede encadenar saltos (cooldown 0,45 s); agachado no salta.
- [ ] Otro cliente ve la pose de agachado (piernas flexionadas, cuerpo más bajo).

### Etapa 3 — Mano
- [ ] Se ve un único brazo en la parte inferior derecha.
- [ ] Clic derecho/F extiende la mano hacia el punto de mira; la rueda/Z-X cambia el alcance.
- [ ] La mano se detiene contra paredes (no las atraviesa) y no se aleja más de `MaxReach`.
- [ ] Con la mano extendida se puede empujar la caja liviana y abrir la puerta empujando.
- [ ] La mano no empuja al propio jugador ni a otros jugadores.
- [ ] Correr/saltar con la mano extendida no produce vibraciones.

### Etapa 4 — Objetos
- [ ] Clic izquierdo sobre la caja liviana: se levanta; al soltar cae por gravedad.
- [ ] Levantarla y dejarla sobre la mesa; queda estable.
- [ ] Moverla rápido y soltar: conserva parte de la velocidad (se puede lanzar suavemente).
- [ ] Caja pesada: el HUD dice "Arrastrar"; se arrastra por el suelo sin levantarse.
- [ ] Llevar la caja contra una pared: no la atraviesa; si se queda atrás, se suelta sola.
- [ ] Objeto lejano (> 8 studs): el HUD indica "Demasiado lejos" y no se agarra.
- [ ] Velocidad reducida al cargar (más con objetos pesados); no se puede correr arrastrando.
- [ ] Bolsa de dinero, lata y caja pequeña se agarran y sueltan bien.
- [ ] Tirar un objeto fuera del mapa: vuelve a su posición inicial.

### Etapa 5 — Interacciones
- [ ] E abre la puerta (hacia el lado contrario al jugador) y la cierra.
- [ ] Agarrar el pomo/hoja de la puerta con clic izquierdo y abrirla tirando con la mano.
- [ ] El cajón se abre con E o tirando; la gema solo se puede recoger con el cajón abierto.
- [ ] E sobre la gema: "+$250 en el bolsillo".
- [ ] El interruptor enciende la luz y la zona de entrega pasa de roja a verde.
- [ ] Puerta de la bóveda bloqueada; el botón la desbloquea; la caja fuerte suelta una bolsa.
- [ ] Bolsa dentro de la zona activa: "+$X entregado"; el botín del equipo sube.
- [ ] Entrar en la zona con la gema en el bolsillo la entrega.
- [ ] El botón de reinicio restaura objetos, bolsas, puertas, energía y botín.
- [ ] **Recorrido completo**: abrir puerta → coger bolsa → interruptor → entregar.

## Pruebas obligatorias con dos clientes (Etapa 6)

Studio → Test → Clients and Servers → 2 Players. Estado actual de todas: **PENDIENTE**.

| # | Prueba | Qué esperar | Por qué debería funcionar |
|---|---|---|---|
| 1 | Ambos entran | 2 personajes, cámara 1ª persona, mano cada uno | `CharacterService` por jugador |
| 2 | Movimiento independiente | cada uno se mueve sin afectar al otro | física de personaje por cliente |
| 3 | A agarra una caja, B la ve | B ve la caja seguir a la mano de A y el brazo de A | caja propiedad de A → se replica; `ArmRenderer` dibuja la mano remota |
| 4 | A suelta, B la recoge | B puede agarrarla en cuanto A suelta | `HeldBy` se borra al soltar |
| 5 | A abre la puerta, B pasa | B ve la puerta abierta y la atraviesa | puerta simulada por el servidor |
| 6 | Agarre simultáneo | solo uno lo consigue; el otro ve "Otro jugador lo está sujetando" | `TryGrab` atómico + `holdsByPart` |
| 7 | Desconexión sosteniendo | el objeto cae, vuelve a ser del servidor y B puede cogerlo | `PlayerRemoving` → `Release` |
| 8 | Objetos distintos a la vez | ambos manipulan sin interferencias | un hold por jugador, propietarios distintos |

Pruebas extra recomendadas: morir sosteniendo un objeto; bloquear la bóveda mientras otro
sujeta la puerta; entregar una bolsa que sostiene otro jugador; 4 jugadores a la vez.

## Pruebas de seguridad recomendadas (con la consola de comandos del cliente)

```lua
-- Desde lejos de la caja (p. ej. en los puntos de aparición) debe devolver false, "TooFar"
game.ReplicatedStorage.Remotes.GrabRequest:InvokeServer(workspace.TestArena.CajaPesada, Vector3.zero)
```

Lanzar `InteractRequest` en bucle debe ser limitado (5/s) sin errores en el servidor.
