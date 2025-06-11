#!/bin/bash

USERNAME_gitHub=""
GITHUB_REPO_URL=""
PROJECT_DIR=""
PROJECT_NAME=""
LOG_DIR="$HOME/vercel_logs"
LOG_FILE=""
REPO_GITHUB=""

# Codes d'erreur
readonly ERR_INVALID_OPTION=100
readonly ERR_MISSING_PARAM=101
readonly ERR_DIR_NOT_FOUND=102
readonly ERR_GITHUB_AUTH=103
readonly ERR_VERCEL_AUTH=104
readonly ERR_DEPLOYMENT=105
readonly ERR_INSTALL=106
readonly ERR_GIT_OPERATION=107
readonly ERR_INVALID_PROJECT=108

# Fonction de gestion d'erreur centralisée
handle_error() {
    local error_code=$1
    local error_message=$2
    local show_help=${3:-true}

    # Log l'erreur
    log_entry "ERROR" "Code $error_code: $error_message"

    # Afficher le message d'erreur
    echo "ERREUR ($error_code): $error_message" >&2

    # Afficher un message spécifique selon le code d'erreur
    case $error_code in
        $ERR_INVALID_OPTION)
            echo "Une option invalide a été spécifiée." >&2
            ;;
        $ERR_MISSING_PARAM)
            echo "Un paramètre obligatoire est manquant." >&2
            ;;
        $ERR_DIR_NOT_FOUND)
            echo "Le répertoire spécifié n'existe pas." >&2
            ;;
        $ERR_GITHUB_AUTH)
            echo "Erreur d'authentification GitHub." >&2
            ;;
        $ERR_VERCEL_AUTH)
            echo "Erreur d'authentification Vercel." >&2
            ;;
        $ERR_DEPLOYMENT)
            echo "Erreur lors du déploiement." >&2
            ;;
        $ERR_INSTALL)
            echo "Erreur lors de l'installation des dépendances." >&2
            ;;
        $ERR_GIT_OPERATION)
            echo "Erreur lors d'une opération Git." >&2
            ;;
        $ERR_INVALID_PROJECT)
            echo "Le projet spécifié n'est pas valide ou est corrompu." >&2
            ;;
        *)
            echo "Une erreur inconnue s'est produite." >&2
            ;;
    esac

    # Afficher l'aide si demandé
    if [ "$show_help" = true ]; then
        echo -e "\nConsultez l'aide pour plus d'informations :"
        afficher_aide
    fi

    # Sortir avec le code d'erreur
    exit $error_code
}

# Initialisation des logs
init_logs() {
    mkdir -p "$LOG_DIR"
    if [ -n "$PROJECT_DIR" ]; then
        PROJECT_NAME=$(basename "$PROJECT_DIR")
        LOG_FILE="$LOG_DIR/${PROJECT_NAME}$(date +"%Y%m%d%H%M%S").log"
    else
        PROJECT_NAME="unknown"
        LOG_FILE="$LOG_DIR/autoDeploy_$(date +"%Y%m%d_%H%M%S").log"
    fi
}

log_entry() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local log_message="$timestamp : $(whoami) : $level : $message"
    
    if [[ "$level" == "ERROR" ]]; then
        echo "$log_message" | tee -a "$LOG_FILE" >&2
    else
        echo "$log_message" | tee -a "$LOG_FILE"
    fi
}

installation() {
    log_entry "INFO" "Début de l'installation des outils nécessaires..."

    ### ==== 0. Fonctions utilitaires ==== ###
    check_cmd() {
        command -v "$1" &> /dev/null
    }

    ### ==== 1. Vérifie et installe GitHub CLI ==== ###
    if ! check_cmd gh; then
        log_entry "INFO" "Installation de GitHub CLI..."
        echo "GitHub CLI (gh) n'est pas installé. Installation en cours..."
        type -p curl >/dev/null || sudo apt install curl -y || handle_error $ERR_INSTALL "Échec de l'installation de curl"
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
            sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg || handle_error $ERR_INSTALL "Échec de l'installation de la clé GitHub CLI"
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg || handle_error $ERR_INSTALL "Échec de la configuration des permissions"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
            sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null || handle_error $ERR_INSTALL "Échec de la configuration du dépôt"
        sudo apt update || handle_error $ERR_INSTALL "Échec de la mise à jour des dépôts"
        sudo apt install gh -y || handle_error $ERR_INSTALL "Échec de l'installation de GitHub CLI"
        echo "GitHub CLI installé avec succès."
        log_entry "SUCCESS" "GitHub CLI installé."
    else
        log_entry "INFO" "GitHub CLI déjà installé."
    fi

    ### ==== 2. Vérifie et installe Vercel CLI ==== ###
    if ! check_cmd vercel; then
        echo "Vercel CLI non détecté. Installation en cours..."
        log_entry "INFO" "Installation de Vercel CLI via npm..."
        
        # Vérifie si npm est installé
        if ! check_cmd npm; then
            echo "npm non détecté. Installation de Node.js..."
            if ! check_cmd curl; then
                sudo apt install curl -y || handle_error $ERR_INSTALL "Échec de l'installation de curl"
            fi
            
            # Installation de NVM
            echo "Installation de NVM (Node Version Manager)..."
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash || handle_error $ERR_INSTALL "Échec de l'installation de NVM"
            
            # Charger NVM sans redémarrer le terminal
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" || handle_error $ERR_INSTALL "Échec du chargement de NVM"
            
            # Installation de Node.js LTS
            echo "Installation de Node.js LTS..."
            nvm install --lts || handle_error $ERR_INSTALL "Échec de l'installation de Node.js"
            nvm use --lts || handle_error $ERR_INSTALL "Échec de l'utilisation de Node.js LTS"
        fi
        
        # Installation de Vercel CLI
        echo "Installation de Vercel CLI..."
        npm install -g vercel || handle_error $ERR_INSTALL "Échec de l'installation de Vercel CLI"
        echo "Vercel CLI installé."
        log_entry "SUCCESS" "Vercel CLI installé."
    else
        log_entry "INFO" "Vercel CLI déjà installé."
    fi

    # Installer les dépendances si requirements.txt existe
    if [ -f "requirements.txt" ]; then
        echo "Installation des dépendances Python..."
        pip install -r requirements.txt || handle_error $ERR_INSTALL "Échec de l'installation des dépendances Python"
        log_entry "INFO" "Dépendances Python installées."
    fi

    # Installer les dépendances Node.js si package.json existe
    if [ -f "package.json" ]; then
        echo "Installation des dépendances Node.js..."
        npm install || handle_error $ERR_INSTALL "Échec de l'installation des dépendances Node.js"
        log_entry "INFO" "Dépendances Node.js installées."
    fi
}

depot_gitHub() {
    log_entry "INFO" "Début de la création/mise à jour du dépôt GitHub..."

    ### ==== 1. Vérifie la connexion à GitHub ==== ###
    if ! gh auth status &> /dev/null; then
        log_entry "INFO" "Connexion à GitHub requise."
        echo "Veuillez vous connecter à GitHub maintenant."
        gh auth login || handle_error $ERR_GITHUB_AUTH "Échec de la connexion à GitHub"
    else
        echo "Déjà connecté à GitHub."
        log_entry "INFO" "Déjà connecté à GitHub."
    fi

    USERNAME_gitHub=$(gh api user --jq '.login') || handle_error $ERR_GITHUB_AUTH "Impossible de récupérer le nom d'utilisateur GitHub"
    log_entry "INFO" "Utilisateur GitHub: $USERNAME_gitHub"

    ### ==== 2. Configuration du projet ==== ###
    if [ -z "$PROJECT_DIR" ]; then
        read -p "Nom du dossier du projet local : " PROJECT_DIR
        [ -z "$PROJECT_DIR" ] && handle_error $ERR_MISSING_PARAM "Le nom du dossier du projet est requis"
    fi
    
    cd "$PROJECT_DIR" || handle_error $ERR_DIR_NOT_FOUND "Dossier '$PROJECT_DIR' introuvable"
    
    if [ -z "$REPO" ]; then
        read -p "Nom du dépôt GitHub à créer : " REPO
        [ -z "$REPO" ] && handle_error $ERR_MISSING_PARAM "Le nom du dépôt est requis"
    fi
    log_entry "INFO" "Nom du repo : $REPO"

    read -p "Rendre le dépôt privé ? (y/n) : " PRIVATE
    if [ "$PRIVATE" == "y" ]; then
        PRIV="--private"
    else
        PRIV="--public"
    fi

    ### ==== 3. Gestion du dépôt Git local ==== ###
    if [ ! -d ".git" ]; then
        echo "Initialisation d'un nouveau dépôt Git"
        git init || handle_error $ERR_GIT_OPERATION "Échec de l'initialisation du dépôt Git"
    else
        echo "Dépôt Git existant détecté"
    fi

    ### ==== 4. Gestion des remotes ==== ###
    REPO_EXISTS=$(gh repo list --json name -q ".[] | select(.name==\"$REPO\") | .name") || \
        handle_error $ERR_GITHUB_AUTH "Impossible de vérifier l'existence du dépôt"
    REMOTE_URL="https://github.com/$USERNAME_gitHub/$REPO.git"
    
    # Nettoyage des remotes existants
    if git remote get-url origin &> /dev/null; then
        echo "Suppression du remote 'origin' existant"
        git remote remove origin || handle_error $ERR_GIT_OPERATION "Échec de la suppression du remote origin"
    fi
    
    # Nettoyage des remotes de sauvegarde s'ils existent
    if git remote get-url origin_old &> /dev/null; then
        echo "Suppression du remote 'origin_old' existant"
        git remote remove origin_old || handle_error $ERR_GIT_OPERATION "Échec de la suppression du remote origin_old"
    fi

    ### ==== 5. Commit des changements ==== ###
    if [ -n "$(git status --porcelain)" ]; then
        echo "Ajout des fichiers modifiés"
        git add . || handle_error $ERR_GIT_OPERATION "Échec de l'ajout des fichiers"
        git commit -m "Deployment commit $(date +%s)" || handle_error $ERR_GIT_OPERATION "Échec du commit"
    fi

    ### ==== 6. Création/Mise à jour du dépôt GitHub ==== ###
    if [ "$REPO_EXISTS" = "$REPO" ]; then
        echo "Le dépôt '$REPO' existe déjà sur votre compte GitHub."
        echo "Connexion au dépôt existant..."
        git remote add origin "$REMOTE_URL" || handle_error $ERR_GIT_OPERATION "Échec de l'ajout du remote"
        git push -u origin master 2>/dev/null || git push -u origin main 2>/dev/null || git push -u origin --all || \
            handle_error $ERR_GIT_OPERATION "Échec du push vers GitHub"
        log_entry "SUCCESS" "Connecté au dépôt GitHub existant et mis à jour."
    else
        echo "Création du dépôt GitHub '$REPO'..."
        gh repo create "$REPO" $PRIV --description "Auto-deployment repository" --clone=false || \
            handle_error $ERR_GITHUB_AUTH "Création repo GitHub échouée"
        
        git remote add origin "$REMOTE_URL" || handle_error $ERR_GIT_OPERATION "Échec de l'ajout du remote"
        git branch -M main 2>/dev/null || true
        git push -u origin main || git push -u origin master || \
            handle_error $ERR_GIT_OPERATION "Échec du push vers GitHub"
        echo "Projet poussé sur GitHub !"
        log_entry "SUCCESS" "Repo GitHub créé et pushé."
    fi

    GITHUB_REPO_URL="https://github.com/$USERNAME_gitHub/$REPO.git"
    REPO_GITHUB="$REPO"
    export GITHUB_REPO_URL
    return 0
}

detect_project_type() {
    if [ -f "package.json" ]; then
        echo "nodejs"
    elif [ -f "requirements.txt" ] || [ -f "app.py" ] || [ -f "main.py" ]; then
        echo "python"
    elif [ -f "index.html" ] || [ -f "index.htm" ]; then
        echo "static"
    elif [ -f "Dockerfile" ]; then
        echo "docker"
    else
        echo "unknown"
    fi
}

deployement_vercel() {
    log_entry "INFO" "Début du déploiement Vercel..."

    ### ==== 1. Vérification du projet ==== ###
    if [ -z "$PROJECT_DIR" ]; then
        read -p "Chemin vers votre projet local à déployer : " PROJECT_DIR
        [ -z "$PROJECT_DIR" ] && handle_error $ERR_MISSING_PARAM "Le chemin du projet est requis"
    fi
    
    [ ! -d "$PROJECT_DIR" ] && handle_error $ERR_DIR_NOT_FOUND "Le dossier '$PROJECT_DIR' n'existe pas"
    cd "$PROJECT_DIR" || handle_error $ERR_DIR_NOT_FOUND "Impossible d'accéder au dossier: $PROJECT_DIR"
    
    PROJECT_NAME=$(basename "$PROJECT_DIR")
    echo "Projet local sélectionné: $PROJECT_NAME"
    echo "Chemin: $PROJECT_DIR"
    log_entry "INFO" "Projet local sélectionné: $PROJECT_NAME dans $PROJECT_DIR"

    ### ==== 2. Vérification de la connexion Vercel ==== ###
    if ! vercel whoami &> /dev/null; then
        echo "Vous n'êtes pas connecté à Vercel. Connexion requise..."
        vercel login || handle_error $ERR_VERCEL_AUTH "Échec de la connexion à Vercel"
    fi

    ### ==== 3. Configuration du projet ==== ###
    if [ -z "$VERCEL_PROJECT_NAME" ]; then
        DEFAULT_VERCEL_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
        read -p "Nom du projet sur Vercel (laissez vide pour '$DEFAULT_VERCEL_NAME') : " VERCEL_PROJECT_NAME
        VERCEL_PROJECT_NAME=${VERCEL_PROJECT_NAME:-$DEFAULT_VERCEL_NAME}
        VERCEL_PROJECT_NAME=$(echo "$VERCEL_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    fi

    [[ ! "$VERCEL_PROJECT_NAME" =~ ^[a-z0-9._-]+$ ]] && handle_error $ERR_INVALID_PROJECT "Nom de projet Vercel invalide: $VERCEL_PROJECT_NAME"

    ### ==== 4. Déploiement ==== ###
    DEPLOY_CMD="vercel --prod --yes --name $VERCEL_PROJECT_NAME"
    PROJECT_TYPE=$(detect_project_type)
    [ "$PROJECT_TYPE" = "static" ] && DEPLOY_CMD="$DEPLOY_CMD --public"
    
    log_entry "INFO" "Commande de déploiement : $DEPLOY_CMD"
    echo "Déploiement sur Vercel..."
    
    $DEPLOY_CMD || handle_error $ERR_DEPLOYMENT "Échec du déploiement sur Vercel"
    
    echo "Projet déployé avec succès sur Vercel !"
    log_entry "SUCCESS" "Déploiement Vercel réussi."
    return 0
}

deployement_gitHubPages() {
	REPO_NAME="$1"
	USERNAME_gitHub=$(gh api user --jq '.login')
	REPO_URL="https://github.com/${USERNAME_gitHub}/${REPO_NAME}.git"
	GH_PAGES_BRANCH="gh-pages"

	# Travailler dans un dossier temporaire pour éviter les interférences
	TEMP_DIR=$(mktemp -d)
	cd "$TEMP_DIR"

	# Cloner le dépôt
	git clone --depth=1 "$REPO_URL" repo-temp
	mkdir gh-pages-temp
	cp -r repo-temp/* gh-pages-temp/
	rm -rf repo-temp

	cd gh-pages-temp
	git init
	git remote add origin "$REPO_URL"
	git checkout -b "$GH_PAGES_BRANCH"
	git add .
	git commit -m "Déploiement GitHub Pages depuis le dépôt distant"
	git push -f origin "$GH_PAGES_BRANCH"

	cd ../..
	rm -rf "$TEMP_DIR"

	echo "Déploiement terminé : https://${USERNAME_gitHub}.github.io/${REPO_NAME}/"
}

# Mode Full : Déploiement projet local vers GitHub + Vercel
full_deployment() {
    local project_path="$1"
    
    log_entry "INFO" "Début du processus Full: Projet local vers GitHub + Vercel"
    echo "Mode Full activé: Projet local vers GitHub et Vercel simultanément"
    
    # Configuration du chemin du projet
    if [ -z "$project_path" ]; then
        read -p "Chemin vers votre projet local : " project_path
    fi
    
    # Vérification de l'existence du projet
    if [ ! -d "$project_path" ]; then
        echo "Le dossier '$project_path' n'existe pas."
        log_entry "ERROR" "Dossier projet introuvable: $project_path"
        return 1
    fi
    
    # Se déplacer dans le dossier du projet
    cd "$project_path" || {
        log_entry "ERROR" "Impossible d'accéder au dossier: $project_path"
        return 1
    }
    
    # Mise à jour des variables globales
    PROJECT_DIR="$project_path"
    PROJECT_NAME=$(basename "$project_path")
    
    echo "Projet détecté: $PROJECT_NAME"
    echo "Chemin: $PROJECT_DIR"
    
    # Demander le nom du repository GitHub
    read -p "Nom du repository GitHub à créer (laisser vide pour utiliser '$PROJECT_NAME') : " REPO_NAME
    if [ -z "$REPO_NAME" ]; then
        REPO_NAME="$PROJECT_NAME"
    fi
    REPO="$REPO_NAME"
    
    echo "Lancement des déploiements en parallèle..."
    
    # Déploiement GitHub en arrière-plan
    (
        echo "[GitHub] Début du déploiement GitHub..."
        if depot_gitHub; then
            echo "[GitHub] Déploiement GitHub terminé avec succès"
            log_entry "SUCCESS" "Full - GitHub deployment completed"
        else
            echo "[GitHub] Échec du déploiement GitHub"
            log_entry "ERROR" "Full - GitHub deployment failed"
        fi
    ) &
    GITHUB_PID=$!

    # Déploiement Vercel en arrière-plan
    (
        echo "[Vercel] Début du déploiement Vercel..."
        sleep 5  # Attendre un peu pour que GitHub se configure
        if deployement_vercel; then
            echo "[Vercel] Déploiement Vercel terminé avec succès"
            log_entry "SUCCESS" "Full - Vercel deployment completed"
        else
            echo "[Vercel] Échec du déploiement Vercel"
            log_entry "ERROR" "Full - Vercel deployment failed"
        fi
    ) &
    VERCEL_PID=$!

    # Attendre que les deux processus se terminent
    echo "Attente de la fin des déploiements..."
    wait $GITHUB_PID
    GITHUB_STATUS=$?
    wait $VERCEL_PID
    VERCEL_STATUS=$?

    # Rapport final
    echo ""
    echo "Rapport du déploiement Full:"
    echo "Projet: $PROJECT_NAME"
    echo "Chemin: $PROJECT_DIR"
    
    if [ $GITHUB_STATUS -eq 0 ]; then
        echo "GitHub: Succès - Repository '$REPO_NAME' créé"
        echo "URL: https://github.com/$USERNAME_gitHub/$REPO_NAME"
    else
        echo "GitHub: Échec"
    fi
    
    if [ $VERCEL_STATUS -eq 0 ]; then
        echo "Vercel: Succès - Application déployée"
    else
        echo "Vercel: Échec"
    fi

    if [ $GITHUB_STATUS -eq 0 ] && [ $VERCEL_STATUS -eq 0 ]; then
        echo ""
        echo "Déploiement Full terminé avec succès!"
        echo "Votre projet est maintenant disponible sur GitHub et Vercel!"
        log_entry "SUCCESS" "Full deployment completed successfully"
        return 0
    else
        echo ""
        echo "Déploiement Full terminé avec des erreurs."
        log_entry "WARNING" "Full deployment completed with errors"
        return 1
    fi
}

show_script_logs() {
    echo "Logs disponibles:"
    if [ -d "$LOG_DIR" ]; then
        ls -lht "$LOG_DIR"/*.log 2>/dev/null | head -10
        echo ""
        echo "Contenu du dernier log:"
        cat "$LOG_DIR"/*.log 2>/dev/null
    else
        echo "Aucun log trouvé dans $LOG_DIR"
    fi
}

afficher_aide() {
    echo "Script de déploiement automatique"
    echo ""
    echo "Utilisation : $0 [OPTIONS] [ARGUMENTS]"
    echo ""
    echo "Options :"
    echo "  -h                      Affiche cette aide"
    echo "  -V                      Déploie uniquement sur Vercel"
    echo "  -G                      Crée ou met à jour uniquement le dépôt GitHub (sans Pages)"
    echo "  -P [nom_de_repo]        Déploie sur GitHub Pages un dépôt déjà existant (préciser son nom)"
    echo "  -Q [chemin_projet]      Déploie un projet local sur GitHub, puis sur GitHub Pages"
    echo "  -f [chemin_projet]      Mode Full : Projet local vers GitHub + Vercel"
    echo "  -l                      Affiche les logs du script"
    echo ""
    echo "Option principale - Mode Full (-f) :"
    echo "  Cette option prend votre projet local et le déploie automatiquement sur :"
    echo "  • GitHub (création d'un nouveau repository)"
    echo "  • Vercel (déploiement de l'application)"
    echo ""
    echo "Exemples :"
    echo "  $0 -V                                    # Déploie sur Vercel seulement"
    echo "  $0 -G                                    # Crée ou met à jour le dépôt GitHub"
    echo "  $0 -P mon-repo                           # Déploie GitHub Pages sur un dépôt déjà existant"
    echo "  $0 -Q /chemin/vers/projet                # Déploie local → GitHub → GitHub Pages"
    echo "  $0 -f /chemin/vers/projet                # Mode Full : local vers GitHub + Vercel"
    echo "  $0 -f                                    # Mode Full (chemin demandé interactivement)"
    echo "  $0 -l                                    # Affiche les logs"
    echo ""
    exit 0
}

# Fonction principale
main() {
    log_entry "INFO" "Début de l'exécution du script pour le projet $PROJECT_NAME."

    # Traitement des options
    while getopts "stVP:QGf:hl" option; do
        case $option in
            s|t) ;; # deja traites
            
            V)
                deployement_vercel || handle_error $ERR_DEPLOYMENT "Échec du déploiement Vercel"
                ;;
            P)
                if [ -z "$OPTARG" ]; then
                    handle_error $ERR_MISSING_PARAM "Le nom du repository est requis pour l'option -P"
                fi
                REPO="$OPTARG"
                deployement_gitHubPages "$REPO" || handle_error $ERR_DEPLOYMENT "Échec du déploiement GitHub Pages"
                ;;
            Q)
                depot_gitHub || handle_error $ERR_GIT_OPERATION "Échec de la création/mise à jour du dépôt GitHub"
                deployement_gitHubPages "$REPO_GITHUB" || handle_error $ERR_DEPLOYMENT "Échec du déploiement GitHub Pages"
                ;;
            G)
                depot_gitHub || handle_error $ERR_GIT_OPERATION "Échec de la création/mise à jour du dépôt GitHub"
                ;;
            f)
                # Mode Full - Projet local vers GitHub + Vercel
                if [ -z "$OPTARG" ]; then
                    handle_error $ERR_MISSING_PARAM "Le chemin du projet est requis pour l'option -f"
                fi
                PROJECT_PATH="$OPTARG"
                full_deployment "$PROJECT_PATH" || handle_error $ERR_DEPLOYMENT "Échec du déploiement Full"
                ;;
            l)
                show_script_logs
                ;;
            h)
                afficher_aide
                ;;
            \?)
                handle_error $ERR_INVALID_OPTION "Option invalide: -$OPTARG"
                ;;
        esac
    done

    # Si aucune option n'est fournie, afficher l'aide
    if [ $OPTIND -eq 1 ]; then
        afficher_aide
    fi
}

# Exécution du script principal

#executer le programme dans un sous shell avec l'option -s
has_s=false
has_t=false

for arg in "$@"; do
    if [[ $arg == -* ]]; then
        if [[ $arg == s ]]; then
            has_s=true
        elif [[ $arg == t ]]; then
            has_t=true
        fi
    fi
done


if $has_s; then
    init_logs # Initialisation
    installation # Installation des outils nécessaires
   
    ( main "$@" )
elif $has_t; then
# Exécution parallèle avec & pour chaque fonction
    # $! :  PID du dernier processus exécuté
    init_logs &     # Thread 1
    pid1=$!

    installation &  # Thread 2
    pid2=$!

    main "$@" &     # Thread 3
    pid3=$!

    # Attendre la fin de tous les threads
    wait $pid1
    wait $pid2
    wait $pid3
else
    init_logs # Initialisation
    installation # Installation des outils nécessaires

    main "$@"
fi