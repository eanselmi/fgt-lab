#!/usr/bin/env bash
#
# Wrapper del lab FortiGate. Descarga Terraform automáticamente (on-first-run)
# desde releases.hashicorp.com a un caché en /tmp (ver CACHE_DIR).
#
# Dos stacks de Terraform independientes, cada uno con su bucket S3 de state
# (lock nativo de S3, use_lockfile, sin DynamoDB). Cada bucket se crea en su
# deploy si no existe y se elimina en su destroy (tras un destroy exitoso):
#   - lab    (aws/,    bucket fgt-lab-<ACCOUNT_ID>):        FortiGates, Windows, red.
#   - budget (budget/, bucket fgt-lab-budget-<ACCOUNT_ID>): alertas de costos y
#     créditos. Se despliega una vez al empezar y no lo afectan los deploy/destroy
#     del lab, así el acumulado de créditos no se reinicia.
#
# Pensado para correr en AWS CloudShell tras un `git clone`, sin instalar nada:
#   ./lab.sh budget deploy   # primero, una sola vez
#   ./lab.sh deploy
#   ./lab.sh destroy
#   ./lab.sh budget destroy  # al terminar el curso
#
set -euo pipefail

TF_VERSION="1.15.8"

# Valor de var.project_name en Terraform: todos los recursos del lab llevan el
# tag Project=<esto> (default_tags) y los budgets se llaman <esto>-*.
PROJECT="fgt-lab"

# Región fija del lab (sizing, precios y AMI del Marketplace validados acá). No
# se toma la de CloudShell: si el alumno la abre en otra región, el lab igual
# va a us-east-1 y el bucket de state se sigue encontrando.
REGION="us-east-1"

# Parámetro SSM con la fecha (YYYY-MM-DD) del primer deploy de la fase 2, para
# que status muestre el día del trial PAYG. No se borra con los destroy: el
# trial es uno solo por cuenta.
TRIAL_PARAM="/$PROJECT/payg-trial-start"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_DIR="$SCRIPT_DIR/aws"
BUDGET_DIR="$SCRIPT_DIR/budget"

# CloudShell solo persiste ~1 GB en $HOME, insuficiente para el binario de
# Terraform (~110 MB) + el provider de AWS descomprimido (~700 MB). Por eso el
# binario y los plugins van al disco efímero grande del entorno (override con
# FGT_LAB_CACHE_DIR). Es efímero: se re-descarga al iniciar una sesión nueva.
CACHE_DIR="${FGT_LAB_CACHE_DIR:-/tmp/fgt-lab-cache}"
BIN_DIR="$CACHE_DIR/bin"
TF="$BIN_DIR/terraform"
# Cada stack tiene su TF_DATA_DIR (ver use_stack); el provider se descarga una
# sola vez y lo comparten por esta caché.
export TF_PLUGIN_CACHE_DIR="$CACHE_DIR/plugins"

usage() {
  cat <<EOF
Uso: ./lab.sh <comando> [fase]
     ./lab.sh budget <deploy|destroy|plan>

Comandos del budget (stack independiente, ejecutalo PRIMERO, una sola vez):
  budget deploy          Crea las alertas por email: gasto real de bolsillo
                         (budget de 1 USD/mes) y creditos (aviso al quedar
                         < 10 USD). Pide tu email. No lo afectan los deploy ni
                         los destroy del lab.
  budget destroy         Elimina las alertas y su bucket de state (al final del
                         curso, despues de ./lab.sh destroy).
  budget plan            Como budget deploy pero sin aplicar (dry-run).

Comandos del lab:
  deploy [fase1|fase2]   Descarga Terraform si falta, crea el bucket de state
                         (si falta), inicializa y despliega. fase1 = ambos
                         FortiGate BYOL; fase2 = FortiGate del SITE-A en PAYG
                         (free trial) con WAN2 + FortiAnalyzer. Sin fase,
                         mantiene la fase desplegada (fase1 si no hay lab).
                         Volver de fase2 a fase1 pide confirmacion.
  destroy                Destruye el lab (pide confirmacion) y, si termina
                         bien, elimina el bucket de state aunque no esté vacío.
  plan [fase1|fase2]     Como deploy pero muestra el plan sin aplicar (dry-run).
  status                 Muestra el estado del lab (instancias, status checks,
                         IPs publicas, Windows/SSM, dia del trial PAYG y
                         creditos) sin cambiar nada.
                         Solo usa la AWS CLI: no necesita Terraform.

En fase2 solo se recrea el FortiGate del SITE-A (PAYG, con WAN2) y se agrega el
FortiAnalyzer; el SITE-B, los Windows y las EIP existentes no cambian.

En deploy/plan se pide (obligatorio) la hora (0-23) de un apagado automático
diario de las instancias, para no dejarlas encendidas por olvido.

Binario de Terraform: $TF (v$TF_VERSION)
Directorios Terraform: $AWS_DIR (lab), $BUDGET_DIR (budget)
EOF
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo ""
  fi
}

ensure_terraform() {
  if [[ -x "$TF" ]]; then
    return
  fi

  for tool in curl unzip; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "ERROR: falta '$tool', necesario para descargar Terraform." >&2
      exit 1
    fi
  done

  local os arch
  case "$(uname -s)" in
    Linux) os="linux" ;;
    Darwin) os="darwin" ;;
    *)
      echo "ERROR: sistema operativo no soportado: $(uname -s)" >&2
      exit 1
      ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) arch="amd64" ;;
    aarch64 | arm64) arch="arm64" ;;
    *)
      echo "ERROR: arquitectura no soportada: $(uname -m)" >&2
      exit 1
      ;;
  esac

  local zip url tmp expected actual
  zip="terraform_${TF_VERSION}_${os}_${arch}.zip"
  url="https://releases.hashicorp.com/terraform/${TF_VERSION}/${zip}"

  echo ">> Terraform no encontrado. Descargando v${TF_VERSION} (${os}_${arch})..."
  mkdir -p "$BIN_DIR"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  curl -fsSL -o "$tmp/$zip" "$url"

  # El checksum es obligatorio: sin SHA256SUMS o sin herramienta de hash no se
  # instala un binario sin verificar.
  if ! curl -fsSL -o "$tmp/SHA256SUMS" \
    "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_SHA256SUMS"; then
    echo "ERROR: no se pudo descargar el SHA256SUMS de Terraform; no se instala sin verificar." >&2
    exit 1
  fi
  expected="$(awk -v f="$zip" '$2 == f {print $1}' "$tmp/SHA256SUMS")"
  actual="$(sha256_of "$tmp/$zip")"
  if [[ -z "$expected" || -z "$actual" ]]; then
    echo "ERROR: no se pudo verificar el checksum de $zip (falta en SHA256SUMS o no hay sha256sum/shasum)." >&2
    exit 1
  fi
  if [[ "$expected" != "$actual" ]]; then
    echo "ERROR: checksum inválido para $zip." >&2
    echo "  esperado: $expected" >&2
    echo "  obtenido: $actual" >&2
    exit 1
  fi

  unzip -o -q "$tmp/$zip" terraform -d "$BIN_DIR"
  chmod +x "$TF"
  echo ">> Terraform instalado en $TF"
}

resolve_env() {
  local console_region
  console_region="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || true)}}"
  # El provider de Terraform y la AWS CLI toman la región de acá.
  export AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION"

  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  if [[ -z "$ACCOUNT_ID" || "$ACCOUNT_ID" == "None" ]]; then
    echo "ERROR: no se pudo obtener el AWS Account ID. ¿Hay credenciales activas?" >&2
    exit 1
  fi

  if [[ -n "$console_region" && "$console_region" != "$REGION" ]]; then
    cat >&2 <<EOF

>> AVISO: tu CloudShell/consola esta en la region $console_region, pero el lab
   siempre va a $REGION (N. Virginia). Cambia la region de la consola (arriba
   a la derecha) a N. Virginia para ver los recursos del lab.

EOF
  fi
}

# Fase desplegada, deducida de EC2 (el FortiAnalyzer solo existe en fase 2).
# Queda vacía si no hay instancias del lab.
detect_current_phase() {
  local names
  names="$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Project,Values=$PROJECT" \
    "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value]' \
    --output text)"
  if grep -q -- '-faz$' <<<"$names"; then
    CURRENT_PHASE="2"
  elif [[ -n "$names" ]]; then
    CURRENT_PHASE="1"
  else
    CURRENT_PHASE=""
  fi
}

# Selecciona el stack de Terraform: directorio, bucket de state y TF_DATA_DIR.
use_stack() {
  case "$1" in
    lab)
      STACK_DIR="$AWS_DIR"
      BUCKET="${PROJECT}-${ACCOUNT_ID}"
      ;;
    budget)
      STACK_DIR="$BUDGET_DIR"
      BUCKET="${PROJECT}-budget-${ACCOUNT_ID}"
      ;;
  esac
  export TF_DATA_DIR="$CACHE_DIR/tfdata-$1"
}

ensure_state_bucket() {
  if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo ">> Bucket de state ya existe: $BUCKET"
    return
  fi

  echo ">> Creando bucket de state: $BUCKET (región $REGION)"
  if [[ "$REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
  fi

  aws s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null
}

tf_init() {
  mkdir -p "$TF_PLUGIN_CACHE_DIR"
  rm -rf "$STACK_DIR/.terraform"
  "$TF" -chdir="$STACK_DIR" init -input=false \
    -backend-config="bucket=$BUCKET" \
    -backend-config="region=$REGION"
}

# Sin fase explícita mantiene la desplegada (CURRENT_PHASE), así un
# `./lab.sh deploy` de costumbre no baja de fase 2 a fase 1.
parse_phase() {
  case "${1:-}" in
    "")
      PHASE="${CURRENT_PHASE:-1}"
      if [[ -n "$CURRENT_PHASE" ]]; then
        echo ">> Sin fase indicada: se mantiene la fase desplegada (fase$PHASE)."
      fi
      ;;
    fase1) PHASE=1 ;;
    fase2) PHASE=2 ;;
    *)
      echo "ERROR: fase inválida: '${1}'. Usá fase1 o fase2." >&2
      exit 1
      ;;
  esac
}

ask_shutdown() {
  local hh tz choice custom

  echo ""
  echo ">> Guardrail: apagado automatico DIARIO de las instancias (obligatorio, cuida tus creditos)."
  while true; do
    if ! read -r -p "   Hora de apagado, solo la hora 0-23 (ej: 13, 16, 05): " hh; then
      echo "ERROR: se requiere una hora de apagado (entrada no interactiva)." >&2
      exit 1
    fi
    if [[ "$hh" =~ ^([0-9]|0[0-9]|1[0-9]|2[0-3])$ ]]; then
      break
    fi
    echo "   Hora invalida '$hh'. Ingresa un numero de 0 a 23." >&2
  done

  echo ""
  echo "   Zona horaria: elegi el numero de tu pais"
  echo "      1) Mexico                (America/Mexico_City)"
  echo "      2) Espana                (Europe/Madrid)"
  echo "      3) Colombia              (America/Bogota)"
  echo "      4) Peru                  (America/Lima)"
  echo "      5) Argentina             (America/Argentina/Buenos_Aires)"
  echo "      6) Chile                 (America/Santiago)"
  echo "      7) Ecuador               (America/Guayaquil)"
  echo "      8) Brasil                (America/Sao_Paulo)"
  echo "      9) Republica Dominicana  (America/Santo_Domingo)"
  echo "     10) Guatemala             (America/Guatemala)"
  echo "     11) Otra (la escribo yo)"
  while true; do
    if ! read -r -p "   Opcion [1-11]: " choice; then
      echo "ERROR: se requiere elegir zona horaria (entrada no interactiva)." >&2
      exit 1
    fi
    case "$choice" in
      1) tz="America/Mexico_City" ;;
      2) tz="Europe/Madrid" ;;
      3) tz="America/Bogota" ;;
      4) tz="America/Lima" ;;
      5) tz="America/Argentina/Buenos_Aires" ;;
      6) tz="America/Santiago" ;;
      7) tz="America/Guayaquil" ;;
      8) tz="America/Sao_Paulo" ;;
      9) tz="America/Santo_Domingo" ;;
      10) tz="America/Guatemala" ;;
      11)
        echo "   Busca tu zona en la columna 'TZ identifier' de:"
        echo "   https://en.wikipedia.org/wiki/List_of_tz_database_time_zones"
        if ! read -r -p "   Ingresa tu zona horaria IANA (ej: Europe/Lisbon): " custom; then
          echo "ERROR: se requiere una zona horaria." >&2
          exit 1
        fi
        if [[ -z "$custom" ]]; then
          echo "   No ingresaste nada, proba de nuevo." >&2
          continue
        fi
        tz="$custom"
        ;;
      *)
        echo "   Opcion invalida '$choice'. Elegi un numero del 1 al 11." >&2
        continue
        ;;
    esac
    break
  done

  SHUTDOWN_CRON="cron(0 $((10#$hh)) ? * * *)"
  SHUTDOWN_TZ="$tz"
  echo ""
  echo "   Apagado programado: $((10#$hh)):00 hs (${tz})"
}

ask_email() {
  local email

  echo ""
  echo ">> Alertas de costos: recibis un aviso por email si hay gasto real de bolsillo"
  echo "   (budget de 1 USD/mes) y cuando te quedan menos de 10 USD de creditos."
  while true; do
    if ! read -r -p "   Tu correo electronico para la alerta: " email; then
      echo "ERROR: se requiere un correo (entrada no interactiva)." >&2
      exit 1
    fi
    if [[ "$email" =~ ^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$ ]]; then
      break
    fi
    echo "   Correo invalido '$email'. Proba de nuevo (ej: nombre@dominio.com)." >&2
  done

  ALERT_EMAIL="$email"
  echo "   Vas a recibir un email de AWS Notifications para CONFIRMAR la suscripcion: aceptalo."
}

# Pide escribir 'si' para continuar; cualquier otra respuesta cancela.
confirm_si() {
  local answer
  if ! read -r -p ">> $1 (escribi 'si' para continuar): " answer; then
    echo ">> Cancelado (entrada no interactiva)." >&2
    exit 1
  fi
  case "$answer" in
    si | Si | SI | s | S) ;;
    *)
      echo ">> Cancelado. No se hizo ningun cambio." >&2
      exit 1
      ;;
  esac
}

confirm_fase2() {
  cat >&2 <<'EOF'

############################################################################
## FASE 2 — FortiGate PAYG (free trial de 30 dias)
##
## Al desplegar la FASE 2 el lab entra en MODO ULTIMOS 30 DIAS:
##   - Solo tiene sentido DESPUES de completar la FASE 1.
##   - El FortiGate del SITE-A pasa a PAYG (free trial de 30 dias, cubre UNA
##     sola instancia) y suma WAN2 (port3). El SITE-B sigue BYOL.
##   - El trial se AUTO-CONVIERTE A PAGO el dia 30: cancela la suscripcion
##     antes. El fee de FortiOS PAYG es un cargo de AWS Marketplace y NO lo
##     cubren los creditos del Free Tier.
##   - Requiere aceptar en Marketplace las suscripciones del FortiGate PAYG y
##     del FortiAnalyzer BYOL.
##   - El FortiGate del SITE-A se RECREA (nueva AMI): se pierde su config de
##     FortiOS (hace backup antes y restore despues). La EIP de WAN1 se
##     conserva y port1/port2 mantienen su rol (WAN1/LAN).
##   - Se agrega un FortiAnalyzer (licencia trial con tu cuenta FortiCare).
##   - ./lab.sh status muestra en que dia del trial estas.
############################################################################
EOF
  confirm_si "Confirmas desplegar la FASE 2?"
}

confirm_fase1() {
  cat >&2 <<'EOF'

############################################################################
## VOLVER A FASE 1 — el lab esta hoy en FASE 2
##
##   - Se BORRA el FortiAnalyzer y el FortiGate PAYG del SITE-A, que se
##     recrea como BYOL: se pierde su config de FortiOS (hace backup antes).
##   - Si solo querias redesplegar la fase 2, cancela y corre:
##       ./lab.sh deploy fase2
##   - Despues cancela la suscripcion PAYG en Marketplace (ver README).
############################################################################
EOF
  confirm_si "Confirmas volver a la FASE 1?"
}

# Guarda la fecha de inicio del trial PAYG si todavía no existe (sin
# --overwrite, put-parameter falla y se conserva la fecha original).
record_trial_start() {
  if aws ssm put-parameter --region "$REGION" --name "$TRIAL_PARAM" \
    --type String --value "$(date -u +%Y-%m-%d)" \
    --tags "Key=Project,Value=$PROJECT" >/dev/null 2>&1; then
    echo ">> Inicio del trial PAYG registrado: $(date -u +%Y-%m-%d). Segui los dias con ./lab.sh status."
  fi
}

# Epoch de una fecha YYYY-MM-DD y fecha DD/MM/YYYY de un epoch (GNU date en
# CloudShell, BSD date en macOS).
epoch_of_date() {
  date -u -d "$1" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d %H:%M:%S" "$1 00:00:00" +%s
}
date_of_epoch() {
  date -u -d "@$1" +%d/%m/%Y 2>/dev/null || date -u -r "$1" +%d/%m/%Y
}

# Día del trial PAYG (solo si la fase 2 está desplegada).
trial_status() {
  local start start_epoch day end
  start="$(aws ssm get-parameter --region "$REGION" --name "$TRIAL_PARAM" \
    --query Parameter.Value --output text 2>/dev/null || true)"
  echo ""
  if [[ ! "$start" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "   Trial PAYG (fase 2): sin fecha registrada. Revisala en Marketplace -> Manage subscriptions."
    return
  fi
  start_epoch="$(epoch_of_date "$start")"
  day=$(( ($(date -u +%s) - start_epoch) / 86400 + 1 ))
  end="$(date_of_epoch $(( start_epoch + 30 * 86400 )))"
  if (( day <= 30 )); then
    echo "   Trial PAYG (fase 2): dia $day de 30, vence el $end."
    echo "     Antes de esa fecha volve a fase 1 y cancela la suscripcion PAYG (ver README)."
  else
    echo "   Trial PAYG (fase 2): VENCIDO el $end (dia $day). El FortiGate PAYG ya se cobra"
    echo "     (~US\$ 0,88 por hora prendido, NO lo cubren los creditos): volve a fase 1 YA."
  fi
  echo "     (Fecha aproximada: cuenta desde el primer deploy de la fase 2; el trial real"
  echo "      arranca al suscribirte en Marketplace.)"
}

lab_status() {
  local tmp ids win_ids
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  echo ">> Estado del lab (cuenta $ACCOUNT_ID, region $REGION)"
  echo ""

  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Project,Values=$PROJECT" \
    "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].[InstanceId, Tags[?Key==`Name`]|[0].Value, State.Name, InstanceType, ImageId]' \
    --output text >"$tmp/inst"

  if [[ ! -s "$tmp/inst" ]]; then
    echo "   No hay instancias del lab en $REGION. Desplegalo con: ./lab.sh deploy"
    return
  fi

  ids="$(awk -F'\t' '{print $1}' "$tmp/inst")"
  # shellcheck disable=SC2046
  aws ec2 describe-images --region "$REGION" \
    --image-ids $(awk -F'\t' '{print $5}' "$tmp/inst" | sort -u) \
    --query 'Images[].[ImageId, Name]' --output text >"$tmp/img" 2>/dev/null || true
  # shellcheck disable=SC2086
  aws ec2 describe-instance-status --region "$REGION" --include-all-instances \
    --instance-ids $ids \
    --query 'InstanceStatuses[].[InstanceId, InstanceStatus.Status, SystemStatus.Status]' \
    --output text >"$tmp/st"

  echo "   Instancias:"
  printf "     %-14s %-20s %-9s %-10s %-10s %s\n" "NOMBRE" "INSTANCE-ID" "ESTADO" "TIPO" "CHECKS" "SOFTWARE"
  awk -F'\t' -v img="$tmp/img" -v st="$tmp/st" '
    BEGIN {
      while ((getline line < img) > 0) { split(line, f, "\t"); name[f[1]] = f[2] }
      while ((getline line < st) > 0) {
        split(line, f, "\t")
        if (f[2] == "ok" && f[3] == "ok") c = "ok"
        else if (f[2] == "not-applicable") c = "-"
        else if (f[2] == "initializing" || f[3] == "initializing") c = "iniciando"
        else c = f[2] "/" f[3]
        chk[f[1]] = c
      }
    }
    {
      n = name[$5]; v = n; sub(/.*\(/, "", v); sub(/\).*/, "", v)
      if (n ~ /FortiGate/) sw = "FortiGate " ((n ~ /ONDEMAND/) ? "PAYG" : "BYOL") " " v
      else if (n ~ /FortiAnalyzer/) sw = "FortiAnalyzer " v
      else if (n ~ /Windows/) sw = "Windows Server"
      else sw = "-"
      printf "     %-14s %-20s %-9s %-10s %-10s %s\n", $2, $1, $3, $4, (chk[$1] == "" ? "-" : chk[$1]), sw
    }' "$tmp/inst" | sort

  if awk -F'\t' '$2 ~ /-faz$/ {found = 1} END {exit !found}' "$tmp/inst"; then
    trial_status
  fi

  echo ""
  echo "   IPs publicas (GUI: https://<IP>, usuario admin, password inicial = instance-id):"
  aws ec2 describe-addresses --region "$REGION" \
    --filters "Name=tag:Project,Values=$PROJECT" \
    --query 'Addresses[].[Tags[?Key==`Name`]|[0].Value, PublicIp]' \
    --output text | sort | awk -F'\t' '{printf "     %-16s %s\n", $1, $2}'

  echo ""
  echo "   Windows (SSM / Fleet Manager):"
  win_ids="$(awk -F'\t' '$2 ~ /-win$/ {print $1}' "$tmp/inst")"
  if [[ -n "$win_ids" ]]; then
    aws ssm describe-instance-information --region "$REGION" \
      --filters "Key=InstanceIds,Values=$(tr '\n' ',' <<<"$win_ids" | sed 's/,$//')" \
      --query 'InstanceInformationList[].[InstanceId, PingStatus, ComputerName]' \
      --output text >"$tmp/ssm"
  else
    : >"$tmp/ssm"
  fi
  awk -F'\t' -v ssm="$tmp/ssm" '
    BEGIN { while ((getline line < ssm) > 0) { split(line, f, "\t"); ping[f[1]] = f[2]; host[f[1]] = f[3] } }
    $2 ~ /-win$/ {
      if (ping[$1] == "") msg = "sin conexion a SSM (falta la salida a internet/NAT por el FortiGate, o esta apagado)"
      else if (host[$1] ~ /\./) msg = ping[$1] ", " host[$1] " (en el dominio)"
      else msg = ping[$1] ", " host[$1] " (fuera de dominio)"
      printf "     %-14s %s\n", $2, msg
    }' "$tmp/inst" | sort
  echo "     (El DC del SITE-A termina de promoverse ~15 min despues del deploy; se ve"
  echo "      como 'en el dominio' recien cuando tiene salida a internet por el FortiGate.)"

  echo ""
  echo "   Creditos y gasto (AWS Budgets, se actualiza unas veces por dia):"
  local credits pocket
  credits="$(aws budgets describe-budget --region us-east-1 --account-id "$ACCOUNT_ID" \
    --budget-name "$PROJECT-credits-remaining" \
    --query '[Budget.CalculatedSpend.ActualSpend.Amount, Budget.BudgetLimit.Amount]' \
    --output text 2>/dev/null || true)"
  pocket="$(aws budgets describe-budget --region us-east-1 --account-id "$ACCOUNT_ID" \
    --budget-name "$PROJECT-budget" \
    --query 'Budget.CalculatedSpend.ActualSpend.Amount' \
    --output text 2>/dev/null || true)"
  if [[ -n "$credits" ]]; then
    awk -v c="$credits" 'BEGIN { split(c, f, /[ \t]+/);
      printf "     Creditos consumidos: USD %.2f de %.2f (quedan ~USD %.2f)\n", f[1], f[2], f[2] - f[1] }'
  else
    echo "     Creditos: sin budget (se crea en el deploy si cargaste un email)."
  fi
  if [[ -n "$pocket" ]]; then
    awk -v p="$pocket" 'BEGIN { printf "     Gasto de bolsillo este mes: USD %.2f (deberia ser 0)\n", p }'
  fi
  echo "     Saldo exacto de creditos: Billing and Cost Management -> Credits."
}

# Fecha YYYY-MM-01 de hace N meses (GNU date en CloudShell, BSD date en macOS).
month_start_ago() {
  if date -u -d "now" >/dev/null 2>&1; then
    date -u -d "$(date -u +%Y-%m-01) -$1 months" +%Y-%m-01
  else
    date -u -v1d -v-"$1"m +%Y-%m-01
  fi
}

# Detecta el primer mes con consumo de la cuenta (≈ apertura de la cuenta, desde
# donde corren los 12 meses de los créditos) para usarlo como inicio del budget
# de créditos. Así un destroy + deploy no pierde lo ya consumido. Usa Cost
# Explorer (USD 0.01 por consulta). Si falla, queda vacío y Terraform usa el mes
# del deploy.
detect_credits_start() {
  local start end first
  start="$(month_start_ago 12)"
  end="$(date -u +%Y-%m-%d)"
  CREDITS_START=""
  first="$(aws ce get-cost-and-usage --region us-east-1 \
    --time-period "Start=$start,End=$end" --granularity MONTHLY \
    --metrics UnblendedCost \
    --filter '{"Dimensions":{"Key":"RECORD_TYPE","Values":["Usage"]}}' \
    --query 'ResultsByTime[?to_number(Total.UnblendedCost.Amount) > `0`] | [0].TimePeriod.Start' \
    --output text 2>/dev/null || true)"
  if [[ "$first" =~ ^[0-9]{4}-[0-9]{2}-01$ ]]; then
    CREDITS_START="${first}_00:00"
    echo ">> Budget de creditos: cuenta desde ${first:0:7} (primer mes con consumo de la cuenta)."
  else
    echo ">> Budget de creditos: sin datos en Cost Explorer (cuenta nueva o sin acceso); cuenta desde el mes del deploy."
  fi
}

# destroy del stack seleccionado (tras confirmar con $1 como descripción) y, si
# termina bien, borra su bucket de state. Sin bucket no hay state: no hay nada
# desplegado de este stack.
stack_destroy() {
  if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo ">> El bucket de state $BUCKET no existe: no hay nada desplegado."
    return
  fi
  echo "" >&2
  echo ">> Se va a BORRAR: $1" >&2
  confirm_si "Confirmas el destroy?"
  tf_init
  local vars=()
  # destroy no usa el email, pero la variable es obligatoria en el stack budget.
  [[ "$STACK_DIR" == "$BUDGET_DIR" ]] && vars+=(-var="alert_email=destroy@example.com")
  "$TF" -chdir="$STACK_DIR" destroy -auto-approve ${vars[@]+"${vars[@]}"}
  echo ">> terraform destroy OK. Eliminando bucket de state: $BUCKET"
  aws s3 rb "s3://$BUCKET" --force
  echo ">> Bucket $BUCKET eliminado."
}

# Avisa (sin bloquear) si las alertas de costos todavía no se desplegaron.
warn_if_no_budget() {
  if ! aws budgets describe-budget --region us-east-1 --account-id "$ACCOUNT_ID" \
    --budget-name "$PROJECT-credits-remaining" >/dev/null 2>&1; then
    cat >&2 <<'EOF'

############################################################################
## AVISO: no estan desplegadas las alertas de costos (budget).
## Corre primero, una sola vez:   ./lab.sh budget deploy
## Sin eso no te va a llegar ningun aviso si aparece gasto real o si te
## quedan pocos creditos. Continuo con el deploy del lab igual.
############################################################################

EOF
  fi
}

cmd="${1:-}"
case "$cmd" in
  deploy)
    resolve_env
    detect_current_phase
    parse_phase "${2:-}"
    if [[ "$PHASE" == "2" && "$CURRENT_PHASE" != "2" ]]; then
      confirm_fase2
    elif [[ "$PHASE" == "1" && "$CURRENT_PHASE" == "2" ]]; then
      confirm_fase1
    fi
    ask_shutdown
    ensure_terraform
    warn_if_no_budget
    use_stack lab
    ensure_state_bucket
    tf_init
    "$TF" -chdir="$STACK_DIR" apply -auto-approve \
      -var="lab_phase=$PHASE" \
      -var="shutdown_cron=$SHUTDOWN_CRON" \
      -var="shutdown_timezone=$SHUTDOWN_TZ"
    if [[ "$PHASE" == "2" ]]; then
      record_trial_start
    fi
    ;;
  destroy)
    ensure_terraform
    resolve_env
    use_stack lab
    stack_destroy "todo el lab (FortiGates, Windows, red, EIP) y su bucket de state. Se pierden las configs de FortiOS (hace backup antes)."
    echo ">> El budget (alertas de costos) NO se toca: sigue activo."
    ;;
  budget)
    case "${2:-}" in
      deploy | plan)
        ask_email
        ensure_terraform
        resolve_env
        use_stack budget
        ensure_state_bucket
        tf_init
        detect_credits_start
        if [[ "$2" == "deploy" ]]; then
          "$TF" -chdir="$STACK_DIR" apply -auto-approve \
            -var="alert_email=$ALERT_EMAIL" \
            -var="credits_start=$CREDITS_START"
        else
          "$TF" -chdir="$STACK_DIR" plan \
            -var="alert_email=$ALERT_EMAIL" \
            -var="credits_start=$CREDITS_START"
        fi
        ;;
      destroy)
        ensure_terraform
        resolve_env
        use_stack budget
        stack_destroy "las alertas de costos (budgets) y su bucket de state. Dejas de recibir avisos de gasto."
        ;;
      *)
        echo "ERROR: usá ./lab.sh budget <deploy|destroy|plan>." >&2
        exit 1
        ;;
    esac
    ;;
  plan)
    resolve_env
    detect_current_phase
    parse_phase "${2:-}"
    ask_shutdown
    ensure_terraform
    warn_if_no_budget
    use_stack lab
    ensure_state_bucket
    tf_init
    "$TF" -chdir="$STACK_DIR" plan \
      -var="lab_phase=$PHASE" \
      -var="shutdown_cron=$SHUTDOWN_CRON" \
      -var="shutdown_timezone=$SHUTDOWN_TZ"
    ;;
  status)
    resolve_env
    lab_status
    ;;
  -h | --help | help)
    usage
    exit 0
    ;;
  "")
    echo "ERROR: falta el comando." >&2
    usage
    exit 1
    ;;
  *)
    echo "ERROR: comando desconocido: $cmd" >&2
    usage
    exit 1
    ;;
esac
