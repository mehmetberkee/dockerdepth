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

# --- Custom Node Bağımlılık Kurulumu Başlangıcı ---
echo "--- Custom Node Bağımlılık Kurulumu Başlangıcı ---"

# Dockerfile'dan gelen aktif node listesini oku (boş değilse)
ACTIVE_NODES_LIST="${ACTIVE_CUSTOM_NODES:-}"

# Kalıcı depolamadaki custom node'ların ana dizini
CUSTOM_NODE_DIR="/runpod-volume/ComfyUI/custom_nodes"

# Sadece aktif node'ların requirement'larının kurulduğunu belirten bayrak dosyası
# Bu dosya, kurulumun tekrar tekrar yapılmasını önler.
REQUIREMENTS_INSTALLED_FLAG="${CUSTOM_NODE_DIR}/.active_requirements_installed"

echo "Aktif node'lar için bağımlılıklar kontrol ediliyor: ${ACTIVE_NODES_LIST}"
echo "Hedef node dizini: ${CUSTOM_NODE_DIR}"
echo "Bayrak dosyası: ${REQUIREMENTS_INSTALLED_FLAG}"

# Ana custom node dizininin kalıcı depolamada var olduğundan emin ol
mkdir -p "$CUSTOM_NODE_DIR"

# Aktif node listesi boş mu veya bayrak dosyası zaten var mı?
if [ -z "$ACTIVE_NODES_LIST" ]; then
  echo "INFO: Ortam değişkeni ACTIVE_CUSTOM_NODES tanımlı değil veya boş. Özel bağımlılık kurulumu atlanıyor."
elif [ -f "$REQUIREMENTS_INSTALLED_FLAG" ]; then
  echo "INFO: Aktif node bağımlılıkları zaten kurulu görünüyor (bayrak dosyası bulundu: $REQUIREMENTS_INSTALLED_FLAG)."
else
  echo "INFO: Bayrak dosyası bulunamadı. Belirtilen aktif node'lar için bağımlılıklar kuruluyor..."
  INSTALL_SUCCESS=true # Başlangıçta tüm kurulumların başarılı olduğunu varsayalım

  # Belirtilen her aktif node için döngü
  for node_name in $ACTIVE_NODES_LIST; do
    node_path="${CUSTOM_NODE_DIR}/${node_name}"
    echo "--> Node kontrol ediliyor: '$node_name' ($node_path)"

    # Node dizini kalıcı depolamada var mı?
    if [ ! -d "$node_path" ]; then
      echo "UYARI: Dizin bulunamadı: '$node_path'. Bu node için bağımlılıklar atlanıyor. Lütfen node'un persistent volume'da olduğundan emin olun."
      continue # Sonraki node'a geç
    fi

    # Bu node dizini içinde (alt klasörler dahil) requirements.txt dosyalarını bul
    # `find ... -print -quit` ile önce dosya var mı diye kontrol edebiliriz, sonra işleyebiliriz.
    if find "$node_path" -name requirements.txt -print -quit | grep -q .; then
        echo "    INFO: '$node_name' içinde requirements.txt dosyaları bulundu, kuruluyor..."
        find "$node_path" -name requirements.txt | while IFS= read -r req_file; do
          # Dosyanın gerçekten var ve okunabilir olduğundan emin olalım
          if [ -f "$req_file" ] && [ -r "$req_file" ]; then
              echo "        >>> Kuruluyor: $req_file"
              pip install --no-cache-dir -r "$req_file"
              if [ $? -ne 0 ]; then
                echo "HATA: '$req_file' dosyasındaki bağımlılıklar kurulamadı." >&2
                INSTALL_SUCCESS=false # Herhangi bir hata olursa bayrağı false yap
              fi
          else
              echo "        UYARI: Bulunan '$req_file' geçerli bir dosya değil veya okunamıyor, atlanıyor."
          fi
        done # while read döngüsü sonu
    else
        echo "    INFO: '$node_name' için requirements.txt bulunamadı, kurulum adımı atlanıyor."
    fi

  done # Node döngüsü sonu

  # Tüm aktif node'ların kurulumları (veya kontrolü) tamamlandıktan sonra:
  # Eğer TÜM kurulumlar başarılı olduysa bayrak dosyasını oluştur
  if [ "$INSTALL_SUCCESS" = true ]; then
    echo "INFO: Aktif node bağımlılıkları başarıyla kuruldu veya mevcut değildi. Bayrak dosyası oluşturuluyor."
    # Bayrak dosyasını oluşturmadan önce dizinin var olduğundan emin ol (zaten yaptık ama garanti)
    mkdir -p "$(dirname "$REQUIREMENTS_INSTALLED_FLAG")"
    touch "$REQUIREMENTS_INSTALLED_FLAG"
  else
    echo "UYARI: Bir veya daha fazla bağımlılık kurulumu başarısız oldu. Bayrak dosyası OLUŞTURULMADI! Kurulum bir sonraki başlatmada tekrar denenecek."
  fi
fi # Bayrak dosyası veya boş liste kontrolü sonu

echo "--- Custom Node Bağımlılık Kurulumu Sonu ---"
# --- Custom Node Requirement Installation End ---


# --- Insightface Modelleri için Sembolik Link Oluşturma Başlangıcı ---

# Kalıcı depolamadaki insightface ana dizini (extra_model_paths.yaml'daki yola göre)
PERSISTENT_INSIGHTFACE_DIR="/runpod-volume/ComfyUI/models/insightface"
# Konteyner içinde insightface'in modelleri aradığı varsayılan/beklenen ana dizin
INTERNAL_INSIGHTFACE_DIR="/comfyui/models/insightface"

echo "Insightface model yolu kontrol ediliyor..."
echo "  Kalıcı Depolama Yolu (Hedef): ${PERSISTENT_INSIGHTFACE_DIR}"
echo "  Konteyner İçi Yol (Link Adı): ${INTERNAL_INSIGHTFACE_DIR}"

# 1. Hedef dizinin kalıcı depolamada var olduğundan emin ol
echo "  Kalıcı depolamada hedef dizin yapısı kontrol ediliyor/oluşturuluyor: ${PERSISTENT_INSIGHTFACE_DIR}/models"
mkdir -p "${PERSISTENT_INSIGHTFACE_DIR}/models"
# ÖNEMLİ NOT: antelopev2 dosyalarınızın tam olarak şurada olduğundan emin olun:
# /runpod-volume/ComfyUI/models/insightface/models/antelopev2/ (det_10g.onnx vb. dosyalar burada olmalı)

# 2. Konteyner içindeki yolda mevcut bir dosya/dizin/bozuk link varsa temizle
if [ -e "${INTERNAL_INSIGHTFACE_DIR}" ] || [ -L "${INTERNAL_INSIGHTFACE_DIR}" ]; then
    echo "  Mevcut ${INTERNAL_INSIGHTFACE_DIR} kaldırılıyor..."
    rm -rf "${INTERNAL_INSIGHTFACE_DIR}"
fi

# 3. Sembolik linki oluştur
echo "  Sembolik link oluşturuluyor: ${INTERNAL_INSIGHTFACE_DIR} -> ${PERSISTENT_INSIGHTFACE_DIR}"
ln -s "${PERSISTENT_INSIGHTFACE_DIR}" "${INTERNAL_INSIGHTFACE_DIR}"

# 4. Linkin başarılı olup olmadığını kontrol et
if [ -L "${INTERNAL_INSIGHTFACE_DIR}" ] && [ -d "${INTERNAL_INSIGHTFACE_DIR}" ]; then
    echo "  SUCCESS: Sembolik link başarıyla oluşturuldu ve hedef dizine erişilebiliyor."
    echo "  ${INTERNAL_INSIGHTFACE_DIR} içeriği:"
    ls -l "${INTERNAL_INSIGHTFACE_DIR}"
else
    echo "  WARNING: Sembolik link oluşturulamadı veya hedef (${PERSISTENT_INSIGHTFACE_DIR}) geçerli değil/erişilemiyor!"
fi

echo "--- Insightface Modelleri için Sembolik Link Oluşturma Sonu ---"


# ComfyUI ve RunPod Handler'ı Başlat
# --extra-model-paths-config yolunun doğru olduğundan emin olalım.
# Dockerfile'da WORKDIR /comfyui iken ADD src/extra_model_paths.yaml ./ yapıldığı için
# dosya /comfyui/extra_model_paths.yaml içinde olacaktır.
COMFYUI_CONFIG_PATH="/comfyui/extra_model_paths.yaml"
if [ ! -f "$COMFYUI_CONFIG_PATH" ]; then
    echo "HATA: ComfyUI ekstra model yolları yapılandırma dosyası bulunamadı: $COMFYUI_CONFIG_PATH"
    # Hata durumunda çıkmak daha iyi olabilir
    exit 1
fi

COMFYUI_BASE_ARGS="--disable-auto-launch --disable-metadata --extra-model-paths-config ${COMFYUI_CONFIG_PATH}"

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    echo "runpod-worker-comfy: ComfyUI (API modu) başlatılıyor..."
    python3 /comfyui/main.py ${COMFYUI_BASE_ARGS} --listen &

    echo "runpod-worker-comfy: RunPod Handler (API modu) başlatılıyor..."
    python3 -u /rp_handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    echo "runpod-worker-comfy: ComfyUI (Worker modu) başlatılıyor..."
    # Worker modunda arka planda (&) çalıştırmak önemli
    python3 /comfyui/main.py ${COMFYUI_BASE_ARGS} &

    # Handler'ın ComfyUI başlamadan önce çalışmaması için kısa bir bekleme eklenebilir (opsiyonel)
    sleep 5

    echo "runpod-worker-comfy: RunPod Handler (Worker modu) başlatılıyor..."
    # Handler ön planda çalışarak konteynerin kapanmasını engeller
    python3 -u /rp_handler.py
fi

echo "--- start.sh Script Tamamlandı ---"