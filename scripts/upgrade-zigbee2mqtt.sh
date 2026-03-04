#!/bin/bash
# Script de mise à jour de Zigbee2mqtt
# Usage: sudo bash upgrade-zigbee2mqtt.sh
#
# Prérequis:
#   - Zigbee2mqtt installé dans /opt/zigbee2mqtt
#   - Node.js géré via nvm (installé pour root)
#   - Service systemd "zigbee2mqtt"

set -euo pipefail

Z2M_DIR="/opt/zigbee2mqtt"
SERVICE_NAME="zigbee2mqtt"
NVM_DIR="${NVM_DIR:-/root/.nvm}"
LOG_FILE="/var/log/zigbee2mqtt-upgrade.log"
MIN_NODE_MAJOR=20

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN:${NC} $*" | tee -a "$LOG_FILE"; }
err() { echo -e "${RED}[$(date '+%H:%M:%S')] ERREUR:${NC} $*" | tee -a "$LOG_FILE"; exit 1; }

# Vérification root
[[ $EUID -eq 0 ]] || err "Ce script doit être exécuté en tant que root (sudo)."

# Charger nvm
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    source "$NVM_DIR/nvm.sh"
    log "nvm chargé depuis $NVM_DIR"
else
    err "nvm introuvable dans $NVM_DIR. Vérifiez votre installation."
fi

# Vérifier la version de Node.js
NODE_VERSION=$(node -v 2>/dev/null | sed 's/v//')
NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
log "Node.js actuel : v${NODE_VERSION}"

if [[ "$NODE_MAJOR" -lt "$MIN_NODE_MAJOR" ]]; then
    warn "Node.js v${NODE_VERSION} est trop ancien (minimum: v${MIN_NODE_MAJOR})."
    log "Mise à jour de Node.js via nvm..."
    nvm install "$MIN_NODE_MAJOR"
    nvm use "$MIN_NODE_MAJOR"
    log "Node.js mis à jour : $(node -v)"
fi

# Vérifier que le répertoire Z2M existe
[[ -d "$Z2M_DIR" ]] || err "Répertoire $Z2M_DIR introuvable."

cd "$Z2M_DIR"

# Récupérer la version actuelle
CURRENT_VERSION=$(node -e "console.log(require('./package.json').version)" 2>/dev/null || echo "inconnue")
log "Version actuelle de Zigbee2mqtt : ${CURRENT_VERSION}"

# Sauvegarder la configuration
BACKUP_DIR="/opt/zigbee2mqtt-backups/$(date '+%Y%m%d_%H%M%S')"
mkdir -p "$BACKUP_DIR"
cp -r "$Z2M_DIR/data" "$BACKUP_DIR/"
log "Configuration sauvegardée dans ${BACKUP_DIR}"

# Arrêter le service
log "Arrêt du service ${SERVICE_NAME}..."
systemctl stop "$SERVICE_NAME" || warn "Le service n'était pas actif."

# Mettre à jour depuis git
log "Récupération des mises à jour..."
git fetch origin
git checkout HEAD -- npm-shrinkwrap.json 2>/dev/null || true
git pull origin master --no-rebase

# Installer les dépendances
log "Installation des dépendances..."
npm ci --production

# Compiler
log "Compilation..."
npm run build

# Récupérer la nouvelle version
NEW_VERSION=$(node -e "console.log(require('./package.json').version)" 2>/dev/null || echo "inconnue")
log "Nouvelle version : ${NEW_VERSION}"

# Redémarrer le service
log "Démarrage du service ${SERVICE_NAME}..."
systemctl start "$SERVICE_NAME"

# Vérifier le statut
sleep 3
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "Zigbee2mqtt est actif."
else
    warn "Le service ne semble pas actif. Vérifiez avec : journalctl -u ${SERVICE_NAME} -n 50"
    warn "Pour restaurer : cp -r ${BACKUP_DIR}/data ${Z2M_DIR}/"
fi

log "====================================="
log "Mise à jour terminée : ${CURRENT_VERSION} -> ${NEW_VERSION}"
log "Backup : ${BACKUP_DIR}"
log "====================================="
