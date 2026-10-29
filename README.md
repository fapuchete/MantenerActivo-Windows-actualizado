# MantenerActivo ⏳

> *La pantalla siempre encendida para que nuestro agente favorito trabaje mientras estamos haciendo flexiones o rezando.*

Es molesto estar cambiando la configuración de energía de Windows cada vez que lanzas a tu agente a trabajar. Y es peor volver y encontrar la pantalla bloqueada, el equipo dormido y al agente esperando en la puerta.

**MantenerActivo** vive en la bandeja del sistema (un reloj de arena que respira), evita que Windows bloquee o apague la pantalla, y cuando termina, lo deja todo como estaba. Sin tocar el plan de energía ni pedir permisos de administrador.

## ¿Qué hace?

| Función | Para qué sirve |
|---|---|
| **Doble mecanismo anti-siesta** | Pide a Windows que mantenga equipo y pantalla despiertos (`PowerCreateRequest` + `SetThreadExecutionState`) y lo reafirma cada 30 s, por si alguien se lo quita. |
| **Simulación de actividad** | F15 (la tecla que nadie usa), mover el ratón 1 píxel y devolverlo, o ambos. |
| **Autodiagnóstico** | Comprueba que la actividad simulada de verdad reinicia la inactividad. Si un método no funciona, cambia al siguiente, y si ninguno sirve te avisa. |
| **Modo educado** | Solo simula si no estás usando el equipo. Si estás tecleando, no te molesta. |
| **Tres formas de pedir tiempo** | Por minutos (bloques de 15), hasta una hora concreta, o **mientras corra un programa**. |
| **Vigila a tu agente** | Eliges un programa de la lista (o escribes su nombre) y la pantalla sigue encendida mientras viva. Cuando se cierra, la sesión termina sola. |
| **Inicio rápido** | 30 min, 1 h, 2 h, 4 h, 8 h o indefinido, desde el menú. |
| **Aviso de 5 minutos** | Un globo avisa antes del fin. Haces clic y te regala 30 minutos más. |
| **Siesta-proof** | Si el equipo suspende y reanuda, o desbloqueas la sesión, vuelve a armar todo solo. |
| **Perro guardián** | Si el script se cae, el lanzador `.vbs` lo relanza y retoma la sesión donde iba. |
| **Aviso de batería** | Te avisa al 20 % y al 10 % si estás sin cargador. Eso sí, sigue forzando la pantalla encendida (eso gasta batería). |
| **Icono con personalidad** | Verde, amarillo cuando quedan 5 min, azul si no tiene hora de fin y rojo si descansa. Respira y trae una barra de tiempo restante. |
| **Arrancar con Windows** | Opcional, desde el menú. Recuerda tu última configuración. |

## Cómo se usa

Necesitas Windows con PowerShell 5.1 (el que ya trae Windows).

1. Descarga o clona este repo.
2. Abre uno de estos:
   - `desbloqueador.bat`: con consola visible, para ver qué hace en cada momento.
   - `Iniciar-MantenerActivo.vbs`: oculto y con perro guardián. Es el recomendado para el día a día.
3. Busca el reloj de arena en la bandeja (junto al reloj de Windows).
4. Haz doble clic para elegir cuánto tiempo, o clic derecho para el menú.
5. Vete a hacer flexiones.

Si quieres un acceso directo con su icono, ejecuta `Crear-Acceso-Directo.ps1`.

## Cómo termina

- Se acaba el tiempo, o el programa vigilado se cierra: la pantalla vuelve a su rutina normal.
- Eliges **Detener** o **Salir**: lo mismo, y no se reanuda al volver.
- Se cierra por un fallo (o apagas Windows con una sesión activa): al volver a abrirse retoma la sesión guardada, si sigue vigente.

La configuración se guarda en `%APPDATA%\MantenerActivo`. Para desinstalar, desmarca «Arrancar con Windows», sal de la app y borra la carpeta.

## Letra pequeña (pero honesta)

- No es magia: si tu empresa bloquea el equipo con una política (GPO/Intune) o la sesión remota está desconectada, ningún script de usuario lo evita del todo. En ese caso, habla con TI.
- Mantener la pantalla encendida gasta batería y, en pantallas OLED, no es lo mejor del mundo. Úsalo con cabeza.
- Respeta las normas de tu lugar de trabajo. Esto es para que tu agente termine su tarea, no para fingir que trabajas.
- Viene sin garantía. Si se te cae el mundo, es culpa del mundo.

## Contribuir

Issues y PRs son bienvenidos, sobre todo si traen mejores chistes o un nuevo método para despertar al equipo.

## Licencia

[MIT](./LICENSE): úsalo, cámbialo y compártelo con libertad.

---

*Hecho con cariño, un poco de cafeína y la esperanza de que el agente termine antes de que acabe la serie.*
