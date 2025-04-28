#!/usr/bin/env bash

echo "--- start.sh Script Başlatıldı ---"

# Use libtcmalloc for better memory management
echo "TCMALLOC için kontrol ediliyor..."
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
if [ -n "$TCMALLOC" ]; then
    export LD_PRELOAD="${TCMALLOC}"
    echo "LD_PRELOAD ayarlandı: ${TCMALLOC}"
else
    echo "libtcmalloc bulunamadı, LD_PRELOAD ayarlanmadı."
fi

# --- Insightface Modelleri için Sembolik Link Oluşturma Başlangıcı ---

# Kalıcı depolamadaki insightface ana dizini (extra_model_paths.yaml'daki yola göre)
PERSISTENT_INSIGHTFACE_DIR="/runpod-volume/ComfyUI/models/insightface"
# Konteyner içinde insightface'in modelleri aradığı varsayılan/beklenen ana dizin
INTERNAL_INSIGHTFACE_DIR="/comfyui/models/insightface"

echo "Insightface model yolu kontrol ediliyor..."
echo "  Kalıcı Depolama Yolu (Hedef): ${PERSISTENT_INSIGHTFACE_DIR}"
echo "  Konteyner İçi Yol (Link Adı): ${INTERNAL_INSIGHTFACE_DIR}"

# 1. Hedef dizinin kalıcı depolamada var olduğundan emin ol
#    insightface kütüphanesi genellikle root altında 'models' alt dizinini arar.
#    Bu yüzden PERSISTENT_INSIGHTFACE_DIR içinde 'models' klasörü olduğundan emin olmalıyız.
#    Eğer antelopev2 modelleriniz doğrudan PERSISTENT_INSIGHTFACE_DIR altında ise
#    models olmadan da çalışabilir, ancak kütüphanenin standart beklentisi /models altıdır.
#    Emin olmak için hem ana dizini hem de 'models' alt dizinini oluşturalım.
echo "  Kalıcı depolamada hedef dizin yapısı kontrol ediliyor/oluşturuluyor: ${PERSISTENT_INSIGHTFACE_DIR}/models"
mkdir -p "${PERSISTENT_INSIGHTFACE_DIR}/models"
# ÖNEMLİ NOT: antelopev2 dosyalarınızın tam olarak şurada olduğundan emin olun:
# /runpod-volume/ComfyUI/models/insightface/models/antelopev2/ (det_10g.onnx vb. dosyalar burada olmalı)

# 2. Konteyner içindeki yolda mevcut bir dosya/dizin/bozuk link varsa temizle
#    Bu, 'ln -s' komutunun hata vermesini önler.
if [ -e "${INTERNAL_INSIGHTFACE_DIR}" ] || [ -L "${INTERNAL_INSIGHTFACE_DIR}" ]; then
    echo "  Mevcut ${INTERNAL_INSIGHTFACE_DIR} kaldırılıyor..."
    rm -rf "${INTERNAL_INSIGHTFACE_DIR}"
fi

# 3. Sembolik linki oluştur
#    ln -s HEDEF LİNK_ADI
echo "  Sembolik link oluşturuluyor: ${INTERNAL_INSIGHTFACE_DIR} -> ${PERSISTENT_INSIGHTFACE_DIR}"
ln -s "${PERSISTENT_INSIGHTFACE_DIR}" "${INTERNAL_INSIGHTFACE_DIR}"

# 4. Linkin başarılı olup olmadığını kontrol et (isteğe bağlı ama faydalı)
if [ -L "${INTERNAL_INSIGHTFACE_DIR}" ] && [ -d "${INTERNAL_INSIGHTFACE_DIR}" ]; then
    echo "  SUCCESS: Sembolik link başarıyla oluşturuldu ve hedef dizine erişilebiliyor."
    echo "  ${INTERNAL_INSIGHTFACE_DIR} içeriği:"
    ls -l "${INTERNAL_INSIGHTFACE_DIR}" # Linkin işaret ettiği yerdeki içeriği gösterir
else
    echo "  WARNING: Sembolik link oluşturulamadı veya hedef (${PERSISTENT_INSIGHTFACE_DIR}) geçerli değil!"
    # Hedef dizinde sorun olabilir (örn. /runpod-volume bağlanmamış olabilir)
fi

echo "--- Insightface Modelleri için Sembolik Link Oluşturma Sonu ---"


# ComfyUI ve RunPod Handler'ı Başlat
# --extra-model-paths-config parametresini ComfyUI komutuna eklediğinizden emin olun!
# Dockerfile'da ./extra_model_paths.yaml olarak kopyalandığı ve WORKDIR /comfyui olduğu için
# doğru yol /comfyui/extra_model_paths.yaml olmalıdır.

COMFYUI_BASE_ARGS="--disable-auto-launch --disable-metadata --extra-model-paths-config /comfyui/extra_model_paths.yaml"

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    echo "runpod-worker-comfy: ComfyUI (API modu) başlatılıyor..."
    python3 /comfyui/main.py ${COMFYUI_BASE_ARGS} --listen &

    echo "runpod-worker-comfy: RunPod Handler (API modu) başlatılıyor..."
    python3 -u /rp_handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    echo "runpod-worker-comfy: ComfyUI (Worker modu) başlatılıyor..."
    python3 /comfyui/main.py ${COMFYUI_BASE_ARGS} &

    echo "runpod-worker-comfy: RunPod Handler (Worker modu) başlatılıyor..."
    python3 -u /rp_handler.py
fi

echo "--- start.sh Script Tamamlandı ---"