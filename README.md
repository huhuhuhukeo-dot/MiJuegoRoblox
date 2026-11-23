# MiJuegoRoblox — Prototipo jugable V1

Juego cooperativo de robos (2–4 jugadores) en primera persona con **una sola mano física**
para manipular el entorno: agarrar, levantar, arrastrar y soltar objetos, abrir puertas y
cajones, accionar interruptores y entregar el botín.

> Estado: código completo de las 6 etapas, verificado de forma estática (compilador Luau,
> Selene, `rojo build`, pruebas unitarias de la lógica pura). **Las pruebas jugables en Roblox
> Studio todavía no se han ejecutado** — ver [`docs/TESTING.md`](docs/TESTING.md).

## Abrir el proyecto en Roblox Studio

El repositorio usa el layout de [Rojo](https://rojo.space) (`default.project.json`).

### Opción A — construir un archivo de lugar (lo más simple)

```bash
rojo build default.project.json -o MiJuegoRoblox.rbxlx
```

Abre `MiJuegoRoblox.rbxlx` en Studio y pulsa **Play**. El escenario de pruebas se genera solo
al iniciar el servidor.

### Opción B — sincronización en vivo (para desarrollar)

1. Instala Rojo 7.x (CLI) y el plugin de Rojo para Studio.
2. En el repositorio: `rojo serve`
3. En Studio: abre un lugar vacío (Baseplate) → plugin Rojo → **Connect**.
4. Ajustes que el plugin no puede sincronizar y hay que fijar a mano en ese lugar:
   * `Workspace.StreamingEnabled = false`
   * Game Settings → Avatar → **R15** (el agachado completo requiere R15)
   * Game Settings → Avatar → escala estándar (el túnel de agachado está medido para ella)

### Probar con dos jugadores

Studio → pestaña **Test** → *Clients and Servers* → `2 Players` → **Start**.
La lista de pruebas multijugador está en [`docs/TESTING.md`](docs/TESTING.md).

## Controles

| Acción | Tecla |
|---|---|
| Moverse / mirar | WASD / ratón |
| Correr | Shift |
| Agacharse (mantener) | Ctrl o C |
| Saltar | Espacio |
| Extender la mano (mantener) | Clic derecho o F |
| Agarrar / soltar (mantener) | Clic izquierdo |
| Alcance de la mano | Rueda del ratón o Z / X |
| Interactuar | E |
| Mostrar/ocultar ayuda | H |

Todos los controles se cambian en `src/shared/Config/Controls.lua`; todos los valores de juego
(velocidades, alcance, masas, fuerzas, límites) en `src/shared/Config/GameConfig.lua`.

## Escenario de pruebas

Se construye por código (`src/server/World/TestArenaBuilder.lua`) si el Workspace no tiene
un `TestArena`:

* **Zona de objetos**: caja liviana, caja pesada (solo arrastrable), bolsa de dinero,
  lata pequeña, caja pequeña y una mesa.
* **Túnel de agachado** (techo a 4,4 studs) para probar que no se puede levantar debajo.
* **Habitación** tras una puerta con bisagra: mesa con bolsa, interruptor de energía,
  cajonera con una gema dentro del cajón, botón que bloquea/desbloquea la bóveda.
* **Bóveda** (puerta bloqueada): caja fuerte que suelta una bolsa al abrirla.
* **Zona de entrega**: solo acepta botín con la energía encendida.
* **Botón de reinicio** junto a los puntos de aparición.

Recorrido esperado: abrir la puerta → coger la bolsa → encender el interruptor → dejar la
bolsa en la zona de entrega.

## Documentación

* [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — estructura, flujo cliente/servidor, red y seguridad, cómo añadir interacciones.
* [`docs/TESTING.md`](docs/TESTING.md) — qué se verificó, cómo, y qué queda pendiente en Studio.
* [`docs/CHANGELOG.md`](docs/CHANGELOG.md) — cambios por etapa y limitaciones conocidas.
