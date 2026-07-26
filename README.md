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
- Aceptar en **AWS Marketplace** la suscripción del producto FortiGate que vayas
  a usar (una sola vez por cuenta):
  - **Fase 1:** FortiGate VM **BYOL**.
  - **Fase 2:** FortiGate VM **PAYG / On-Demand** (free trial 30 días).

  Si no aceptás la suscripción, el despliegue falla al crear el FortiGate con un
  error `OptInRequired`.

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

- **Bedrock** también se automatiza: el script invoca un modelo serverless de
  Amazon (Nova Micro, vía Converse API) con un prompt — equivale al playground.
  Los modelos se **auto-habilitan al primer invoke** (ya no hay página de "model
  access"). Si el primer invoke falla por propagación, reintentá con
  `./tasks bedrock`.
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
| `./lab.sh deploy [fase1\|fase2]` | Despliega el lab. `fase1` (default) = FortiGate BYOL; `fase2` = FortiGate PAYG. |
| `./lab.sh plan [fase1\|fase2]`   | Muestra qué se va a crear/cambiar, sin aplicar. |
| `./lab.sh destroy`               | Destruye todo el lab y borra el bucket de state. |

La **única diferencia** entre `fase1` y `fase2` es la AMI y el tipo de instancia
del FortiGate; la red, el Windows y las IPs públicas no cambian.

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

- A esa hora (en punto), **todos los días**, las 4 instancias se apagan solas.
- Solo **apaga** (nunca prende) y es inofensivo si ya estaban apagadas.
- Complementa que las instancias se crean **apagadas**: vos las prendés para
  practicar, y si te olvidás de apagarlas, el guardrail lo hace por vos.

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

---

## Qué se despliega

Dos sitios (VPCs), sin solaparse para permitir el túnel entre ellos:

| Sitio  | VPC CIDR        | Subnets públicas | Subnets privadas |
|--------|-----------------|------------------|------------------|
| SITE-A | `10.210.0.0/16` | 2 (en 2 AZ)      | 2 (en 2 AZ)      |
| SITE-B | `10.220.0.0/16` | 2 (en 2 AZ)      | 2 (en 2 AZ)      |

Por cada sitio:

- **1 FortiGate** en la subnet pública AZ-0, con:
  - **2 interfaces WAN** (2 ENIs, cada una con su **Elastic IP**) → necesarias para
    **SD-WAN**, que requiere mínimo 2 enlaces públicos.
  - **1 interfaz LAN** en la subnet privada, que es el gateway del Windows.
  - `source/dest check` **deshabilitado** en las 3 interfaces (para que el FGT
    pueda rutear/NATear el tráfico del Windows).
- **1 Windows Server 2022** en la subnet privada, **sin IP pública**, detrás del
  FortiGate.
- La route table privada manda `0.0.0.0/0` a la interfaz **LAN** del FortiGate.

> Las instancias se crean **apagadas** para cuidar los créditos. Encendelas cuando
> vayas a trabajar (desde la consola EC2 o con `aws ec2 start-instances`).

---

## Cómo acceder

Al terminar `deploy`, Terraform imprime los **outputs** con los datos de acceso
(los podés volver a ver con `./lab.sh plan` o mirando la salida del deploy).

### FortiGate

- **GUI:** `https://<EIP-WAN1>` (output `fortigate_public_ips`).
- **Usuario:** `admin`
- **Password inicial:** el **instance-id** del FortiGate (output
  `fortigate_instance_ids`).
- El acceso SSH (puerto 22) está **cerrado** a propósito; usá la GUI (tiene consola
  CLI web).

### Windows (por Fleet Manager, sin key pair)

El Windows no tiene IP pública ni RDP expuesto. Se accede por **interfaz gráfica**
usando **AWS Systems Manager → Fleet Manager → Remote Desktop**:

1. Consola de AWS → **Systems Manager** → **Fleet Manager**.
2. Seleccioná la instancia del Windows (output `windows`).
3. **Node actions** → **Connect with Remote Desktop**.
4. Elegí **User credentials** e ingresá:
   - **Usuario:** `Administrator`
   - **Password:** `Fortinet1!`

Se abre el escritorio del Windows en el navegador, sin necesidad de key pair ni de
exponer RDP.

> ⚠️ **Importante:** el acceso por Fleet Manager funciona **recién después de
> configurar el NAT en el FortiGate**. El Windows llega a los endpoints de SSM
> saliendo a internet **a través del FortiGate**; hasta que no configures esa
> salida, Fleet Manager no puede conectarse.

---

## Fase 2 (FortiGate PAYG / free trial)

```bash
./lab.sh deploy fase2
```

Esto **recrea los FortiGate** con la AMI PAYG (y un tipo con más RAM para
FortiGuard). Tener en cuenta:

- El fee de FortiOS PAYG es un **cargo de AWS Marketplace** y **NO lo cubren los
  créditos** del Free Tier.
- El free trial **se auto-convierte a pago el día 30**: **cancelá la suscripción
  antes** (poné un recordatorio y un budget alert).
- Requiere haber aceptado la suscripción del **producto PAYG** (distinta a la BYOL).
- Se **conservan las Elastic IP** (van en las interfaces, no en la instancia), así
  que la IP del túnel no cambia. Pero **se pierde la config de FortiOS** (instancia
  nueva): hacé **backup** de la config antes y **restore** después.

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
  (p. ej. password de Windows fija, acceso admin del FortiGate abierto por
  defecto). No usar este código tal cual en producción.
