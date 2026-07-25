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
TF="$SCRIPT_DIR/bin/terraform"
AWS_DIR="$SCRIPT_DIR/aws"

usage() {
  cat <<EOF
Uso: ./lab.sh <comando>

Comandos:
  deploy    Descarga Terraform si falta, crea el bucket de state (si falta),
            inicializa y despliega (terraform apply -auto-approve).
  destroy   Destruye el lab (terraform destroy -auto-approve) y, si termina
            bien, elimina el bucket de state aunque no esté vacío.
  plan      Como deploy pero muestra el plan sin aplicar (dry-run).

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
  mkdir -p "$SCRIPT_DIR/bin"
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

  unzip -o -q "$tmp/$zip" terraform -d "$SCRIPT_DIR/bin"
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
  "$TF" -chdir="$AWS_DIR" init -input=false \
    -backend-config="bucket=$BUCKET" \
    -backend-config="region=$REGION"
}

cmd="${1:-}"
case "$cmd" in
  deploy)
    ensure_terraform
    resolve_env
    ensure_state_bucket
    tf_init
    "$TF" -chdir="$AWS_DIR" apply -auto-approve
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
    ensure_terraform
    resolve_env
    ensure_state_bucket
    tf_init
    "$TF" -chdir="$AWS_DIR" plan
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
