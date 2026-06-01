REPORTS_DIR = "/home/station-blanche/rapports"

# Endpoint REST — GET /reports
# Retourne la liste des rapports disponibles avec leurs données
@app.route('/reports', methods=['GET'])
def list_reports():
    try:

        # Vérifie que le dossier de rapports existe avant de le parcourir
        if not os.path.exists(REPORTS_DIR):
            return jsonify({'error': 'Dossier introuvable'}), 404

        files = []

        for filename in os.listdir(REPORTS_DIR):
            filepath = os.path.join(REPORTS_DIR, filename)

            # Filtre : on ne liste que les fichiers .txt (rapports texte)
            if os.path.isfile(filepath) and filename.endswith('.txt'):
                stat = os.stat(filepath)

                files.append({
                    'name': filename,
                    'size': stat.st_size,
                    'modified': datetime.datetime.fromtimestamp(
                        stat.st_mtime
                    ).isoformat()
                })

        return jsonify({'reports': files}), 200
    
    # Capture toute erreur inattendue et la renvoie en JSON
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# Endpoint pour récupérer le contenu d'un rapport spécifique
# Lit le fichier demandé et renvoie son contenu en JSON.
@app.route('/reports/<path:filename>', methods=['GET'])
def get_report(filename):

    # sécurité anti path traversal (pas de .. ou qui commence par /)
    if '..' in filename or filename.startswith('/'):
        return jsonify({'error': 'Nom de fichier invalide'}), 400

    # construction du chemin complet vers le fichier 
    filepath = os.path.join(REPORTS_DIR, filename)

    # vérification que le fichier existe bien
    if not os.path.isfile(filepath):
        return jsonify({'error': 'Fichier introuvable'}), 404

    # uniquement les .txt
    if not filename.endswith('.txt'):
        return jsonify({'error': 'Format non autorisé'}), 403

    # Lecture du fichier et envoie du contenue
    try:
        # ouverture fichier avec UTF-8 pour caractères accentués
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        # On retourne le nom du fichier ET son contenu au format JSON.
        return jsonify({
            'filename': filename,
            'content': content
        }), 200

    except Exception as e:
        return jsonify({'error': str(e)}), 500