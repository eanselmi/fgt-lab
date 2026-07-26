#!/usr/bin/env bash
#
# Wrapper del lab FortiGate. Usa el binario de Terraform en bin/terraform; si no
# existe, lo descarga automáticamente (on-first-run) desde releases.hashicorp.com.
#
# El state se guarda en un bucket S3 llamado fgt-lab-<AWS_ACCOUNT_ID>, con lock
# nativo de S3 (use_lockfile, sin DynamoDB). El bucket se crea en deploy si no
# existe y se elimina en destroy (tras un terraform destroy exitoso).
#
# Pensado para correr en AWS CloudShell tras un `git clone`, sin instalar nada:
#   ./lab.sh deploy
#   ./lab.sh destroy
#
set -euo pipefail

TF_VERSION="1.15.8"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_DIR="$SCRIPT_DIR/aws"

# CloudShell solo persiste ~1 GB en $HOME, insuficiente para el binario de
# Terraform (~110 MB) + el provider de AWS descomprimido (~700 MB). Por eso el
# binario y los plugins van al disco efímero grande del entorno (override con
# FGT_LAB_CACHE_DIR). Es efímero: se re-descarga al iniciar una sesión nueva.
CACHE_DIR="${FGT_LAB_CACHE_DIR:-/tmp/fgt-lab-cache}"
BIN_DIR="$CACHE_DIR/bin"
TF="$BIN_DIR/terraform"
export TF_DATA_DIR="$CACHE_DIR/tfdata"

usage() {
  cat <<EOF
Uso: ./lab.sh <comando> [fase]

Comandos:
  deploy [fase1|fase2]   Descarga Terraform si falta, crea el bucket de state
                         (si falta), inicializa y despliega. fase1 = FortiGate
                         BYOL (default); fase2 = FortiGate PAYG free trial.
  destroy                Destruye el lab y, si termina bien, elimina el bucket
                         de state aunque no esté vacío.
  plan [fase1|fase2]     Como deploy pero muestra el plan sin aplicar (dry-run).

La única diferencia entre fase1 y fase2 es la AMI y el tipo de instancia del
FortiGate; el resto (red, Windows, EIP) no cambia.

En deploy/plan se pide (obligatorio) la hora (0-23) de un apagado automático
diario de las instancias, para no dejarlas encendidas por olvido.

Binario de Terraform: $TF (v$TF_VERSION)
Directorio Terraform:  $AWS_DIR
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

  if curl -fsSL -o "$tmp/SHA256SUMS" \
    "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_SHA256SUMS"; then
    expected="$(awk -v f="$zip" '$2 == f {print $1}' "$tmp/SHA256SUMS")"
    actual="$(sha256_of "$tmp/$zip")"
    if [[ -n "$expected" && -n "$actual" && "$expected" != "$actual" ]]; then
      echo "ERROR: checksum inválido para $zip." >&2
      echo "  esperado: $expected" >&2
      echo "  obtenido: $actual" >&2
      exit 1
    fi
  fi

  unzip -o -q "$tmp/$zip" terraform -d "$BIN_DIR"
  chmod +x "$TF"
  echo ">> Terraform instalado en $TF"
}

resolve_env() {
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || true)}}"

  if [[ -z "$ACCOUNT_ID" || "$ACCOUNT_ID" == "None" ]]; then
    echo "ERROR: no se pudo obtener el AWS Account ID. ¿Hay credenciales activas?" >&2
    exit 1
  fi
  if [[ -z "$REGION" ]]; then
    echo "ERROR: no se pudo determinar la región (AWS_REGION / AWS_DEFAULT_REGION)." >&2
    exit 1
  fi

  BUCKET="fgt-lab-${ACCOUNT_ID}"
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
  rm -rf "$AWS_DIR/.terraform"
  "$TF" -chdir="$AWS_DIR" init -input=false \
    -backend-config="bucket=$BUCKET" \
    -backend-config="region=$REGION"
}

parse_phase() {
  case "${1:-fase1}" in
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
  echo ">> Alerta de costos: recibis un aviso por email si el gasto se acerca a 1 USD."
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

confirm_fase2() {
  local answer
  cat >&2 <<'EOF'

############################################################################
## FASE 2 — FortiGate PAYG (free trial de 30 dias)
##
## Al desplegar la FASE 2 el lab entra en MODO ULTIMOS 30 DIAS:
##   - Solo tiene sentido DESPUES de completar la FASE 1 (conectividad BYOL).
##   - Arranca el free trial del FortiGate PAYG (30 dias). El trial se
##     AUTO-CONVIERTE A PAGO el dia 30: cancela la suscripcion antes.
##   - El fee de FortiOS PAYG es un cargo de AWS Marketplace y NO lo cubren
##     los creditos del Free Tier.
##   - Requiere haber aceptado la suscripcion del producto PAYG en Marketplace.
##   - Los FortiGate se RECREAN (nueva AMI): se pierde la config de FortiOS
##     (backup/restore), pero las EIP se conservan.
############################################################################
EOF
  if ! read -r -p ">> Confirmas desplegar la FASE 2? (escribi 'si' para continuar): " answer; then
    echo ">> Cancelado (entrada no interactiva)." >&2
    exit 1
  fi
  case "$answer" in
    si | Si | SI | s | S) ;;
    *)
      echo ">> Cancelado. No se despliega la fase 2." >&2
      exit 1
      ;;
  esac
}

cmd="${1:-}"
case "$cmd" in
  deploy)
    parse_phase "${2:-}"
    [[ "$PHASE" == "2" ]] && confirm_fase2
    ask_shutdown
    ask_email
    ensure_terraform
    resolve_env
    ensure_state_bucket
    tf_init
    "$TF" -chdir="$AWS_DIR" apply -auto-approve \
      -var="lab_phase=$PHASE" \
      -var="shutdown_cron=$SHUTDOWN_CRON" \
      -var="shutdown_timezone=$SHUTDOWN_TZ" \
      -var="alert_email=$ALERT_EMAIL"
    ;;
  destroy)
    ensure_terraform
    resolve_env
    tf_init
    "$TF" -chdir="$AWS_DIR" destroy -auto-approve
    echo ">> terraform destroy OK. Eliminando bucket de state: $BUCKET"
    if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
      aws s3 rb "s3://$BUCKET" --force
      echo ">> Bucket $BUCKET eliminado."
    else
      echo ">> El bucket $BUCKET no existe; nada que borrar."
    fi
    ;;
  plan)
    parse_phase "${2:-}"
    ask_shutdown
    ask_email
    ensure_terraform
    resolve_env
    ensure_state_bucket
    tf_init
    "$TF" -chdir="$AWS_DIR" plan \
      -var="lab_phase=$PHASE" \
      -var="shutdown_cron=$SHUTDOWN_CRON" \
      -var="shutdown_timezone=$SHUTDOWN_TZ" \
      -var="alert_email=$ALERT_EMAIL"
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
