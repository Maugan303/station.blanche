REPORTS_DIR = "/home/station-blanche/rapports"

# Endpoint pour lister les rapports disponibles
@app.route('/reports', methods=['GET'])
def list_reports():
    try:
        if not os.path.exists(REPORTS_DIR):
            return jsonify({'error': 'Dossier introuvable'}), 404

        files = []

        for filename in os.listdir(REPORTS_DIR):
            filepath = os.path.join(REPORTS_DIR, filename)

            # uniquement les fichiers texte
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

    except Exception as e:
        return jsonify({'error': str(e)}), 500
