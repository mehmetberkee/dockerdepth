# Stage 1: Base image with common dependencies
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 as base

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
# git'e hala ihtiyaç olabilir (eğer start.sh içinde klonlama yapacaksanız) veya bazı pip paketleri için.
RUN apt-get update && apt-get install -y \
    python3.10 python3-pip git wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 libxext6 libxrender1 \
 && ln -sf /usr/bin/python3.10 /usr/bin/python \
 && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install comfy-cli
RUN pip install --no-cache-dir comfy-cli

# Install ComfyUI
# --workspace /comfyui kullanıldığı için ComfyUI /comfyui altına kurulacak
RUN /usr/bin/yes | comfy --workspace /comfyui install --cuda-version 11.8 --nvidia --version 0.3.18

# Change working directory to ComfyUI
WORKDIR /comfyui

# --------------------------------------------------------------------------
#      CUSTOM NODE KURULUMU ARTIK IMAJDA YAPILMAYACAK - start.sh HALLEDECEK
# --------------------------------------------------------------------------
# # — 1) Klonlanacak node repo’larının listesi (KALDIRILDI)
# ARG CUSTOM_NODE_REPOS="..."

# # — 2) Hepsini /comfyui/custom_nodes altına klonla (KALDIRILDI)
# RUN set -eux; \
#     # ... git clone komutları ...

# # — 3) requirements.txt bulunan klasörleri bulup kur (KALDIRILDI)
# RUN find /comfyui/custom_nodes -name requirements.txt | while read -r req_file; do \
#     # ... pip install komutları ...
# --------------------------------------------------------------------------

# --- Aktif Node'ları Tanımla (start.sh için) ---
# start.sh script'inin persistent volume'da hangi node klasörlerindeki
# requirements.txt dosyalarını işleyeceğini belirtir.
# İSİMLERİN persistent volume'daki KLASÖR İSİMLERİYLE EŞLEŞTİĞİNDEN EMİN OLUN!
ENV ACTIVE_CUSTOM_NODES="cg-use-everywhere comfyui-kjnodes pulid-comfyui comfyui-pulid-flux-ll comfyui_controlnet_aux comfyui_essentials"
# -------------------------------------------------

# --- Temel Python Paketleri (İsteğe bağlı, imajda tutulabilir) ---
# Pillow gibi sık kullanılan veya ComfyUI'ın kendisinin ihtiyaç duyabileceği paketler.
RUN pip install --no-cache-dir \
    packaging filetype pillow
# ----------------------------------------------------------------

# ---------------- PuLID için Gerekli Bağımlılıkları Kur ------------------
# Bunlar temel ML kütüphaneleri olduğu için imajda kalması mantıklıdır.

# facexlib için gerekli olabilecek sistem kütüphanesi
RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 1. facexlib'i kur
RUN pip install --no-cache-dir --use-pep517 facexlib

# 2. insightface'in belirli sürümünü (0.7.3) ve onnxruntime-gpu'yu PyPI'dan kur
RUN pip install --no-cache-dir insightface==0.7.3 onnxruntime-gpu

# --------------------------------------------------------------------------

# Install runpod
RUN pip install --no-cache-dir runpod requests

# Support for the network volume
# extra_model_paths.yaml'ı /comfyui/ içine kopyalar (WORKDIR /comfyui olduğu için)
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Add scripts
# start.sh, rp_handler.py vb. scriptleri kök dizine kopyalar
ADD src/start.sh src/rp_handler.py test_input.json ./
# restore_snapshot.sh artık kullanılmıyor, onu ADD satırından çıkarabilirsin (opsiyonel)
# ADD src/restore_snapshot.sh ./ # Bu satırı kaldır veya yorum satırı yap

# Kopyalanan scriptlere çalıştırma izni ver
RUN chmod +x /start.sh /rp_handler.py
# RUN chmod +x /restore_snapshot.sh # Bu satırı kaldır veya yorum satırı yap

# Snapshot dosyası kopyalama ve çalıştırma adımları kaldırıldı
# ADD *snapshot*.json /
# RUN /restore_snapshot.sh

# Start container
CMD ["/start.sh"]