# Laboratorio FortiGate en AWS

Laboratorio para el **curso de FortiGate**. Despliega, en tu propia cuenta de AWS
y con un solo comando, dos "sitios" (VPCs) conectables por internet, cada uno con
un **FortiGate** y una **workstation Windows**, para practicar conectividad
(IPsec/SD-WAN) y luego las features licenciadas (web filter, IPS, application
control).

Todo se maneja desde **AWS CloudShell**: no necesitás instalar nada en tu
computadora. El binario de Terraform se descarga solo.

## Arquitectura

![Diagrama del laboratorio: dos VPC (SITE-A y SITE-B), cada una con un FortiGate de 2 WAN con EIP y un Windows privado detrás](docs/FGT%20LAB.jpg)

---

## Requisitos

- Una **cuenta de AWS** donde seas **administrador** (sin restricciones de IAM).
- **Creá la cuenta en Paid account plan (NO uses Free plan).** Al registrarte,
  AWS te deja elegir el plan: elegí **Paid plan**.
  - Los **US$ 100 de bienvenida + los US$ 100 por actividades los recibís igual**
    en Paid plan (los créditos no dependen del plan). No perdés nada por elegir
    Paid.
  - El **Free plan bloquea** los tipos de instancia que no son free-tier-eligible
    (solo permite `t2.micro`/`t3.micro`), y el lab usa `t2.small` / `t3.medium` /
    `c6i.large`. En Free plan el `deploy` falla con `InvalidParameterCombination:
    The specified instance type is not eligible for Free Tier`.
  - En Paid plan **no te cobran nada mientras te alcancen los créditos** (el lab
    está pensado para gastar US$ 0 de bolsillo).
  - **¿Ya la creaste en Free plan?** Upgradeá desde Billing and Cost Management →
    cambiar de plan → **Paid plan**. Los créditos se conservan (aplican 12
    meses). Hacelo **directo desde Billing**; NO uniéndote a una AWS Organization
    / Control Tower, porque eso **expira los créditos al instante**.
- Aceptar en **AWS Marketplace** la suscripción de cada producto (una sola vez
  por cuenta):
  - **Fase 1:** FortiGate VM **BYOL**.
  - **Fase 2:** FortiGate VM **PAYG / On-Demand** (free trial 30 días) y
    **FortiAnalyzer BYOL**. ⚠️ Suscribite al PAYG **recién al empezar la fase
    2**, no antes, para no consumir días del trial.

  Si no aceptás la suscripción, el despliegue falla al crear la instancia con un
  error `OptInRequired`.
- **Dos cuentas FortiCare** (una por FortiGate BYOL): cada cuenta admite una
  sola licencia de evaluación activa. Para relicenciar un FortiGate nuevo (por
  ejemplo, tras un `destroy`), desasociá el anterior de la cuenta.

CloudShell ya trae `git`, `aws`, `curl` y `unzip`; no hace falta instalar nada.

---

## Créditos extra (antes de empezar)

Las cuentas nuevas reciben **US$ 100** al registrarse y pueden ganar **US$ 100
más** completando 5 tareas rápidas (EC2, Lambda, RDS, Budgets y Bedrock). Para
llegar a los **US$ 200** y tener margen de sobra en el lab, el repo trae un
script que **automatiza las 5 tareas**:

```bash
./tasks deploy     # crea EC2 + Lambda + RDS + Budget y ejecuta Bedrock
# ... una vez que se acreditaron los créditos ...
./tasks destroy    # borra todo eso
```

- **Bedrock**: el script invoca un modelo (Claude Sonnet 4.6, con fallback a
  Nova) vía Converse API con un prompt. Los modelos de Amazon se auto-habilitan
  al primer invoke; **Claude/Anthropic puede pedir enviar una vez el formulario
  de caso de uso en la consola**. ⚠️ Si la tarea **no acredita** por CLI, hacela
  a mano en el **playground de la consola** (Amazon Bedrock → Chat/Text
  playground → elegir modelo → mandar un prompt); es 1 minuto.
- Corré `./tasks destroy` apenas se acrediten los créditos, para no gastar de más.

---

## Uso rápido

En **AWS CloudShell**:

```bash
git clone <URL-de-este-repo> fgt-lab
cd fgt-lab
./lab.sh deploy       # despliega la Fase 1 (BYOL)
```

Para destruir todo cuando termines:

```bash
./lab.sh destroy
```

### Comandos

| Comando | Qué hace |
|---------|----------|
| `./lab.sh deploy [fase1\|fase2]` | Despliega el lab. `fase1` (default) = ambos FortiGate BYOL; `fase2` = FortiGate del SITE-A en PAYG + WAN2 + FortiAnalyzer. |
| `./lab.sh plan [fase1\|fase2]`   | Muestra qué se va a crear/cambiar, sin aplicar. |
| `./lab.sh destroy`               | Destruye todo el lab y borra el bucket de state. |
| `./lab.sh status`                | Muestra el estado del lab sin cambiar nada: instancias (prendida/apagada, status checks, versión de FortiOS), IPs públicas, Windows conectados a SSM (y si el DC ya está en el dominio) y créditos consumidos. No necesita Terraform. |

En `fase2` solo se recrea el FortiGate del SITE-A y se agrega el FortiAnalyzer;
el SITE-B, los Windows y las IPs públicas existentes no cambian. Ver
[Fases del lab](#fases-del-lab).

### Apagado automático (obligatorio, para cuidar los créditos)

Para que **nadie se quede sin créditos** por dejar los equipos prendidos, cada
`deploy` (o `plan`) programa un **apagado automático diario** de las instancias.

Es **obligatorio**: al correr el comando, el script te pide **a qué hora** querés
que se apaguen solas (solo la hora, `0`-`23`, ej: `13`, `16`, `05`) y tu **zona
horaria** — la elegís de una **lista numerada de países** (o la opción `11` para
escribirla vos). No se puede saltear.

> Si tu país no está en la lista, buscá tu zona en la columna **"TZ identifier"**
> de [esta tabla](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)
> (ej: `Europe/Lisbon`, `America/Costa_Rica`) y usá la opción `11`.

- A esa hora (en punto), **todos los días**, todas las instancias del lab se
  apagan solas.
- Solo **apaga** (nunca prende) y es inofensivo si ya estaban apagadas.
- Después de cada `deploy` las instancias quedan **prendidas** (el Windows del
  SITE-A tiene que terminar de promoverse a domain controller, ~15 min).
  **Si no vas a practicar en ese momento, apagalas vos** cuando termine la
  promoción del DC (por ejemplo, cuando ya puedas entrar a `SITEA-DC` como
  `FORTILAB\Administrator`): si no, quedan prendidas consumiendo créditos
  hasta la hora del apagado automático, que puede ser casi un día entero.

> Ojo: si estás trabajando cuando llega esa hora, se te van a apagar igual.
> Elegí una hora en la que seguro no estés practicando (ej: la madrugada). Podés
> volver a prenderlas cuando quieras.

### Alerta de costos por email (budget)

El lab está pensado para gastar **US$ 0** (todo cubierto por créditos). Como red
de seguridad, el `deploy` te pide tu **correo electrónico** y crea un **budget de
US$ 1** que te **avisa por email al 50% (US$ 0,50) y al 100% (US$ 1)** si empieza
a haber gasto real de bolsillo — por ejemplo el fee de FortiOS PAYG, que **no**
lo cubren los créditos.

Además se crea un **segundo budget enfocado en los créditos**: te avisa (al mismo
email) cuando te quedan **menos de US$ 10 de créditos**, para que no te agarre
por sorpresa que se agoten.

- Cuando confirmes el deploy, AWS te manda un email de **AWS Notifications** para
  **confirmar la suscripción**: hacé clic en el link, si no, no vas a recibir los
  avisos.
- El primer budget mide **gasto real de bolsillo** (después de aplicar créditos);
  el segundo mide **consumo de créditos** (gasto bruto, antes de créditos).
- El total de créditos se asume en **US$ 200** (`credit_total`); si tu cuenta
  tiene otro monto, ajustá esa variable.
- El budget de créditos cuenta desde el **día 1 del mes del primer deploy**. Si
  hacés `./lab.sh destroy` y volvés a desplegar en otro mes, el contador arranca
  de cero y **no incluye lo ya consumido**: el aviso de "menos de US$ 10" va a
  llegar tarde. Revisá el saldo real en Billing → Credits.

---

## Qué se despliega

Dos sitios (VPCs), sin solaparse para permitir el túnel entre ellos. Todas las
subnets de un sitio van en la **misma AZ** (las ENI del FortiGate tienen que
estar en la AZ de la instancia):

| Sitio  | VPC CIDR        | WAN1 (pública)  | WAN2 (pública)  | LAN (privada)    |
|--------|-----------------|-----------------|-----------------|------------------|
| SITE-A | `10.210.0.0/16` | `10.210.0.0/24` | `10.210.1.0/24` | `10.210.10.0/24` |
| SITE-B | `10.220.0.0/16` | `10.220.0.0/24` | `10.220.1.0/24` | `10.220.10.0/24` |

Por cada sitio:

- **1 FortiGate** con este mapeo de puertos (igual en todas las fases, así un
  backup/restore entre BYOL y PAYG no cambia los nombres de interfaz):

  | Puerto | Rol  | Subnet | IP pública | Cuándo |
  |--------|------|--------|------------|--------|
  | `port1` | WAN1 | pública 1 | Elastic IP | Siempre |
  | `port2` | LAN  | privada   | —          | Siempre (gateway del Windows) |
  | `port3` | WAN2 | pública 2 | Elastic IP | Solo el FortiGate PAYG (fase 2), para SD-WAN/ECMP |

  La licencia de evaluación BYOL admite **3 interfaces, 3 policies y 3 rutas**:
  por eso en BYOL el FortiGate tiene solo 2 puertos y queda **una interfaz libre
  para el túnel IPsec**.
- **1 Windows Server 2022** en la LAN, **sin IP pública**, detrás del FortiGate.
  - **SITE-A:** `SITEA-DC`, **domain controller** del dominio `fortilab.local`
    (NetBIOS `FORTILAB`) con **DNS** y **NPS (RADIUS)**, para las lecciones de
    Firewall Authentication y FSSO. Se promueve solo en el primer arranque
    (~15 min, con 2 reinicios).
  - **SITE-B:** `SITEB-WIN`, workstation.
- La route table privada manda `0.0.0.0/0` a la interfaz **LAN** del FortiGate.
- **Security groups abiertos** (todo el tráfico, entrada y salida): el lab es
  para aprender FortiGate, así que el filtrado lo hace el FortiGate y no AWS.
  VIP, DNAT, IPsec y administración funcionan sin tocar nada en AWS.
- **Fase 2:** además, un **FortiAnalyzer** en la subnet WAN1 del SITE-A, con su
  propia Elastic IP.

### Fases del lab

El lab sigue la **FortiOS 8.0 Administrator Study Guide**. Las versiones de
FortiOS (FortiGate BYOL y PAYG) están fijadas en **8.0.1** para que todo el
curso use la misma GUI.

| Fase | Qué hay | Lecciones |
|------|---------|-----------|
| `fase1` | 2 FortiGate **BYOL** (WAN1 + LAN), DC en SITE-A | 01, 03, 04 (estático), 05, 06, 07 (conceptos), 11 (básico), 14, 15 |
| `fase2` | FortiGate del SITE-A en **PAYG** (+WAN2) + **FortiAnalyzer**; SITE-B sigue BYOL | 02, 04 (ECMP), 07 (SSL inspection), 08, 09, 10, 11 (redundante\*), 12 |
| HA (próximamente) | 2 FortiGate BYOL en cluster | 13 |

\* **VPN redundante: a validar.** El FortiGate del SITE-B (BYOL) no tiene
interfaces para 2 túneles; la idea es que actúe como servidor **dial-up** (una
sola interfaz de túnel que recibe los 2 túneles de WAN1 y WAN2 del SITE-A). Si no
entra en los límites de la licencia eval, este lab queda como teoría.

---

## Cómo acceder

Al terminar `deploy`, Terraform imprime los **outputs** con los datos de acceso
(los podés volver a ver con `./lab.sh plan` o mirando la salida del deploy).

### FortiGate

- **GUI:** `https://<EIP-WAN1>` (output `fortigate_public_ips`).
- **Usuario:** `admin`
- **Password inicial:** el **instance-id** del FortiGate (output
  `fortigate_instance_ids`).
- El FortiGate BYOL se licencia con tu **cuenta FortiCare** al primer login.

### Windows (por Fleet Manager, sin key pair)

El Windows no tiene IP pública ni RDP expuesto. Se accede por **interfaz gráfica**
usando **AWS Systems Manager → Fleet Manager → Remote Desktop**:

1. Consola de AWS → **Systems Manager** → **Fleet Manager**.
2. Seleccioná la instancia del Windows (output `windows`).
3. **Node actions** → **Connect with Remote Desktop**.
4. Elegí **User credentials** e ingresá:
   - **Usuario:** `Administrator` (en el DC del SITE-A es el administrador del
     dominio: `FORTILAB\Administrator`)
   - **Password:** `Fortinet1!`

Se abre el escritorio del Windows en el navegador, sin necesidad de key pair ni de
exponer RDP.

> ⚠️ **Importante:** el acceso por Fleet Manager funciona **recién después de
> configurar el NAT en el FortiGate**. El Windows llega a los endpoints de SSM
> saliendo a internet **a través del FortiGate**; hasta que no configures esa
> salida, Fleet Manager no puede conectarse.

### FortiAnalyzer (fase 2)

- **GUI:** `https://<public_ip>` (output `fortianalyzer`).
- **Usuario:** `admin` — **Password inicial:** el instance-id (output
  `fortianalyzer`).
- Licencia trial permanente con tu cuenta FortiCare: hasta **3 dispositivos** y
  **1 GB/día** de logs.
- El FortiGate del SITE-A le manda logs por la IP privada; el del SITE-B, por la
  IP pública.

---

## Fase 2 (FortiGate PAYG / free trial)

```bash
./lab.sh deploy fase2
```

Esto **recrea el FortiGate del SITE-A** con la AMI PAYG (y un tipo con más RAM
para FortiGuard), le agrega **WAN2** (`port3`) y despliega el **FortiAnalyzer**.
El FortiGate del SITE-B sigue BYOL. Tener en cuenta:

- El fee de FortiOS PAYG es un **cargo de AWS Marketplace** y **NO lo cubren los
  créditos** del Free Tier.
- El free trial **se auto-convierte a pago el día 30**: **cancelá la suscripción
  antes** (poné un recordatorio y un budget alert).
- El free trial cubre **una sola instancia**: por eso solo el SITE-A pasa a PAYG.
- Requiere haber aceptado las suscripciones del **FortiGate PAYG** (distinta a la
  BYOL) y del **FortiAnalyzer BYOL**.
- Se **conserva la Elastic IP de WAN1** (va en la interfaz, no en la instancia),
  así que la IP del túnel no cambia. Pero **se pierde la config de FortiOS**
  (instancia nueva): hacé **backup** de la config antes y **restore** después.
  `port1` y `port2` mantienen su rol, así que la config restaurada sigue
  sirviendo.

---

## State (dónde se guarda)

El estado de Terraform se guarda en un bucket S3 llamado
`fgt-lab-<TU-ACCOUNT-ID>`, que el script **crea automáticamente** en el `deploy` y
**elimina** en el `destroy`. El bucket usa lock nativo de S3 (sin DynamoDB) y tiene
el acceso público bloqueado.

---

## Notas

- El binario de Terraform (v1.15.8) y los plugins se descargan a un directorio
  temporal de CloudShell (`/tmp/fgt-lab-cache`) porque el disco persistente del
  home es de solo 1 GB. Es normal que se re-descargue (~30 s) en una sesión nueva.
- **Costos aun con las instancias apagadas:** se siguen cobrando el almacenamiento
  **EBS** y las **IP públicas (IPv4)** 24/7. Lo que se ahorra apagando —que es lo
  caro— son las **horas de cómputo**. Para cortar todo, usá `./lab.sh destroy`.
- Es un laboratorio de curso: prioriza la simplicidad. Hay concesiones a propósito
  (p. ej. password de Windows fija, security groups totalmente abiertos y GUI del
  FortiGate expuesta a internet). No usar este código tal cual en producción.
