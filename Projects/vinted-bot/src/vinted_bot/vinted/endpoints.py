"""Documentation des endpoints Vinted API (reverse-engineerés Phase 8a + 8b).

═══════════════════════════════════════════════════════════════════════════════
HEADERS REQUIS POUR TOUS LES APPELS D'ÉCRITURE (POST/PUT/PATCH/DELETE)
═══════════════════════════════════════════════════════════════════════════════

  - Cookies du navigateur (export "Get cookies.txt LOCALLY")
  - `Authorization: Bearer <access_token_web>`  (le JWT du cookie)
  - `User-Agent`           — UA réaliste
  - `Referer: https://www.vinted.fr/`
  - `Accept-Language: fr-FR,fr;q=0.9,en;q=0.8`
  - `X-Anon-Id: <anon_id cookie>`
  - **`X-Csrf-Token: <csrf>`** ⚠️ INDISPENSABLE pour les writes
  - `Content-Type: application/json`

Le `X-Csrf-Token` est généré côté navigateur (probablement injecté dans le HTML
de la page d'accueil). On le récupérera en parsant la page `/` au démarrage du
client, puis on le réutilisera pour la durée de la session.

═══════════════════════════════════════════════════════════════════════════════
LECTURE — TOUS VALIDÉS ✅
═══════════════════════════════════════════════════════════════════════════════

  GET /api/v2/wardrobe/{user_id}/items?per_page=N&page=M[&status=DRAFT|SOLD]
    → liste les items (titre, prix, photos preview, brand/size/status en string)
    → PAS de `description` ni d'IDs numériques

  GET /api/v2/items/{item_id}/photos
    → liste des photos avec `url`, `full_size_url`, `width`, `height`, `is_main`

  GET /items/{item_id}-{slug}                                    (HTML)
    → contient <script type="application/ld+json"> avec description complète

  GET /api/v2/users/{user_id}                                    profil public

═══════════════════════════════════════════════════════════════════════════════
ÉCRITURE — VALIDÉS Phase 8b
═══════════════════════════════════════════════════════════════════════════════

  PUT /api/v2/item_upload/items/{item_id}
    Met à jour un item existant (utilisé par l'optimizer + le bumper republish).
    Body JSON complet :

    {
      "item": {
        "id": <item_id>,                  # absent pour POST création
        "currency": "EUR",
        "temp_uuid": "<uuid>",            # = upload_session_id
        "title": "...",
        "description": "...",
        "brand_id": 117878,
        "brand": "Brandit",               # str aussi (redondant)
        "catalog_id": 263,                # = category_id
        "isbn": null,
        "is_unisex": false,
        "ai_photo": false,
        "price": 35,                      # int en EUR
        "package_size_id": 3,             # 1=Petit, 2=Moyen, 3=Grand
        "shipment_prices": {"domestic": null, "international": null},
        "color_ids": [29],
        "assigned_photos": [
          {"id": 33832034692, "orientation": 0},
          ...
        ],
        "measurement_length": null,
        "measurement_width": null,
        "item_attributes": [
          {"code": "condition", "ids": [6]},
          {"code": "size", "ids": [210]}
        ],
        "manufacturer": null,
        "manufacturer_labelling": null
      },
      "feedback_id": null,
      "push_up": false,
      "parcel": null,
      "upload_session_id": "<uuid same as temp_uuid>"
    }

    Réponse 200 :
    {"item": {"id": <item_id>}, "after_upload_actions": [], "code": 0}

═══════════════════════════════════════════════════════════════════════════════
ENDPOINTS COLLATÉRAUX (du flow d'upload) — UTILES pour bumper
═══════════════════════════════════════════════════════════════════════════════

  POST /api/v2/item_upload/suggestions/categories
    Body: {"image_metadata":[{"image_id":"...","orientation":"0"},...],
           "upload_session_id":"<uuid>"}
    Renvoie des suggestions de catégorie d'après les photos.

  POST /api/v2/item_upload/pricing_suggestions
    Body: {"image_metadata":{...}, "item_attributes":[{"field_name":"catalog","value":263},...]}
    Renvoie une fourchette de prix conseillée + items similaires vendus.

  POST /api/v2/item_upload/attributes
    Body: {"attributes":[{"code":"category","value":[263]}]}
    Renvoie les attributs requis pour une catégorie (taille, couleur, état...).
    ⚠️ Réponse énorme (12 KB) avec tous les value_ids possibles.

  POST /api/v2/offline_verification/eligibility
    Body: {"item_attributes":[{"field_name":"brand","value":...}, ...]}
    Check si l'item est éligible à la vérification offline.

  POST https://api.vinted.fr/shipping-estimation/external/package_sizes/suggestion
    Body: payload complet de l'item (catalog_id, brand_id, size_id, title, description...)
    Renvoie {"package_size_id": N} pour pré-remplir le bon format de colis.

═══════════════════════════════════════════════════════════════════════════════
MAPPINGS DÉCOUVERTS (depuis Capture 1, item "Pantalon cargo Brandit Adven")
═══════════════════════════════════════════════════════════════════════════════

  catalog_id 263       = catégorie "Pantalons cargo" (sous-catégorie homme)
  brand_id   117878    = "Brandit"
  size_id    210       = "XL" pour catalog 263 (pantalons homme)
  color_id   29        = "Moutarde"
  status/condition 6   = "Neuf avec étiquette"
  package_size 1-3     = Petit/Moyen/Grand (suggéré par shipping-estimation)

→ Ces IDs sont stables. On peut les capturer pour chaque item au moment du
  bump (en interrogeant l'endpoint d'edit GET ou en parsant le HTML/JSON-LD).

═══════════════════════════════════════════════════════════════════════════════
UPLOAD PHOTO — VALIDÉ Phase 8b-bis ✅
═══════════════════════════════════════════════════════════════════════════════

  POST /api/v2/photos
    Content-Type: multipart/form-data
    Body multipart, 3 champs :
      photo[type]      = "item"
      photo[file]      = <binary, image/jpeg>  (avec filename="...")
      photo[temp_uuid] = "<uuid v4>"  (= upload_session_id, GROUPE les uploads)

    Headers (en plus des standards) :
      X-CSRF-Token, X-Anon-Id, Origin: https://www.vinted.fr

    Réponse 200 :
    {
      "id": 28348263411,                   # ← à utiliser dans assigned_photos
      "width": 450,
      "height": 800,
      "temp_uuid": "<uuid same>",
      "url": "https://images1.vinted.net/t/.../f800/....webp?s=...",
      "dominant_color": "#3D3D3C",
      "dominant_color_opaque": "#C5C5C5",
      "thumbnails": [{"type":"thumb70x100","url":"..."}, ...]
    }

    ⚠️ Vinted convertit en WebP côté serveur. On envoie du JPEG, il stocke du WebP.

═══════════════════════════════════════════════════════════════════════════════
CRÉATION ITEM — VALIDÉ Phase 8b-bis ✅
═══════════════════════════════════════════════════════════════════════════════

  POST /api/v2/item_upload/items                    (URL sans /{id}, méthode POST)
    Content-Type: application/json
    Body : identique au PUT update, mais avec `"item.id": null`
    upload_session_id = même uuid que celui utilisé pour les POST /api/v2/photos

    Réponse 200 :
    {
      "item": {"id": 9181519429},          # ← nouvel item_id à sauvegarder en DB
      "after_upload_actions": ["show_upload_another_item_tip"],
      "code": 0
    }

  ⚠️ L'item est **publié immédiatement** et visible sur Vinted. Pour un test
  sans risque, supprimer juste après création.

═══════════════════════════════════════════════════════════════════════════════
WORKFLOW BUMPER COMPLET (republier un item)
═══════════════════════════════════════════════════════════════════════════════

  1. GET  /api/v2/wardrobe/{user_id}/items?per_page=N&page=M
        → choisir un item éligible (pas bumpé depuis 5j+)

  2. GET  /api/v2/items/{item_id}/photos
        → récupérer les URLs full_size de toutes les photos

  3. Pour chaque photo : télécharger + transformer (Pillow, anti-pHash)

  4. Générer un upload_session_id (uuid v4)

  5. Pour chaque photo transformée :
        POST /api/v2/photos  (multipart, avec upload_session_id)
        → garder le `id` retourné

  6. GET  /items/{item_id}-{slug}   (HTML)
        → extraire description via JSON-LD + tous les attributs
          (brand_id, catalog_id, size, condition, color, price...)

  7. DELETE /api/v2/items/{old_item_id}   (à confirmer dans Phase 8c)

  8. POST /api/v2/item_upload/items
        Body : reprendre tous les attributs + assigned_photos = nouveaux photo_ids
               item.id = null, upload_session_id = celui de l'étape 4
        → reçoit le nouvel item_id à sauvegarder en DB

═══════════════════════════════════════════════════════════════════════════════
SUPPRESSION ITEM — VALIDÉ Phase 8b-bis ✅
═══════════════════════════════════════════════════════════════════════════════

  POST /api/v2/items/{item_id}/delete
    ⚠️ Méthode POST, pas DELETE. URL avec suffixe /delete.
    Headers : standards (X-CSRF-Token, X-Anon-Id, Auth Bearer, cookies)
    Body    : vide
    Réponse : {"code":0,"message":"Ok","message_code":"ok"}

═══════════════════════════════════════════════════════════════════════════════
ENDPOINT BONUS : "items similaires" / "more from user"
═══════════════════════════════════════════════════════════════════════════════

  GET /api/v2/items/{item_id}/more?content_source=other_user_items&screen=item
    Renvoie d'autres items du même user — utile éventuellement pour le bumper
    si on veut éviter de re-republier deux items proches au même moment.

═══════════════════════════════════════════════════════════════════════════════
ENCORE À CAPTURER (optionnel)
═══════════════════════════════════════════════════════════════════════════════

  ❓ POST /oauth/token  grant_type=refresh_token
      Pour le refresh JWT toutes les ~30 min.
      Captable en laissant la page ouverte ~35 min puis faire une action.
      → Si pas dispo, fallback : ré-exporter manuellement les cookies tous les ~mois
        (le refresh_token_web a une durée de vie beaucoup plus longue, ~30 jours).
"""
