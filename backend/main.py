import sys
import os
import time
import glob
import uuid
import secrets
import tempfile
import threading
import warnings
import base64
import urllib.request

os.environ["GRPC_VERBOSITY"] = "ERROR"
os.environ["GLOG_minloglevel"] = "2"
warnings.filterwarnings("ignore")

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import yt_dlp
from google import genai

app = FastAPI()

# Yerelde "flutter run" ile test ederken (farklı port) isteklerin engellenmemesi için
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- AYARLAR (hepsi ortam değişkeninden okunur, koda anahtar YAZMA) ---
API_KEY = os.environ.get("GEMINI_API_KEY")
MODEL_NAME = os.environ.get("GEMINI_MODEL", "gemini-3.5-flash-lite")
# Opsiyonel: tanımlarsan sadece şifreyi bilenler kullanabilir (kotanı korur)
ERISIM_SIFRESI = os.environ.get("ERISIM_SIFRESI")
# Aynı anda en fazla kaç tarif işlensin (ücretsiz sunucunun RAM'i az)
ESZAMANLI_LIMIT = int(os.environ.get("ESZAMANLI_LIMIT", "2"))

if not API_KEY:
    print("HATA: GEMINI_API_KEY ortam değişkeni tanımlı değil.", file=sys.stderr)
    sys.exit(1)

client = genai.Client(api_key=API_KEY)
mesgul_kilidi = threading.Semaphore(ESZAMANLI_LIMIT)


def uzun_linke_cevir(url):
    """TikTok kısa linklerini (vt/vm.tiktok.com) uzun linke çevirir."""
    if "tiktok.com" in url:
        try:
            req = urllib.request.Request(
                url,
                headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"},
            )
            with urllib.request.urlopen(req, timeout=15) as response:
                return response.url
        except Exception:
            return url
    return url


def download_media(url):
    """Videoyu geçici klasöre indirir, dosya yolunu döndürür. Başarısızsa None."""
    prefix = os.path.join(tempfile.gettempdir(), f"gecici_medya_{uuid.uuid4().hex[:8]}")
    ydl_opts = {
        "format": "best",
        "outtmpl": prefix + ".%(ext)s",
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "noprogress": True,
        "http_headers": {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            "Accept-Language": "tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7",
        },
    }
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            path = ydl.prepare_filename(info)
            if os.path.exists(path):
                return path
            found = glob.glob(prefix + ".*")
            return found[0] if found else None
    except Exception as e:
        print(f"İndirme Hatası: {e}", file=sys.stderr)
        return None


PROMPT = """
Lütfen TÜMÜNÜ BÜYÜK HARFLE YAZMA. Normal cümle düzeninde yaz.
Sen usta bir şefsin. Bu videodaki yemeğin tarifini analiz et.
Çıktıyı emojiler kullanarak şu düzende ver:

🍽️ [Yemeğin Adı]

🛒 Malzemeler
• (Malzemeleri alt alta listele)

👨‍🍳 Yapılışı
1. (Adımları sırasıyla anlat)

💡 Şefin Tavsiyesi
(Kısa bir not bırak)
"""


def generate_recipe(file_path):
    """Tarif metnini döndürür. Hata olursa RuntimeError fırlatır."""
    video_file = None
    try:
        video_file = client.files.upload(file=file_path)

        while video_file.state.name == "PROCESSING":
            time.sleep(3)
            video_file = client.files.get(name=video_file.name)

        if video_file.state.name == "FAILED":
            raise RuntimeError("Google sunucusu bu videonun formatını okuyamadı.")

        max_deneme = 3
        son_hata = None
        for deneme in range(max_deneme):
            try:
                response = client.models.generate_content(
                    model=MODEL_NAME,
                    contents=[video_file, PROMPT],
                )
                if response.text:
                    return response.text
                raise RuntimeError("Yapay zeka boş cevap döndürdü.")
            except Exception as e:
                son_hata = e
                if ("503" in str(e) or "429" in str(e)) and deneme < max_deneme - 1:
                    time.sleep(3 * (deneme + 1))
                    continue
                break
        raise RuntimeError(f"Yapay zeka hatası: {son_hata}")
    finally:
        if video_file is not None:
            try:
                client.files.delete(name=video_file.name)
            except Exception:
                pass


# --- WEB SERVİSİ (FASTAPI) ENDPOINTLERİ ---
class TarifIstegi(BaseModel):
    link: str
    sifre: str = ""


@app.get("/saglik")
def saglik_kontrolu():
    return {"durum": "calisiyor"}


@app.post("/tarif-getir")
def tarif_getir_api(veri: TarifIstegi):
    if ERISIM_SIFRESI and not secrets.compare_digest(veri.sifre, ERISIM_SIFRESI):
        raise HTTPException(status_code=401, detail="Şifre yanlış veya eksik.")

    if not mesgul_kilidi.acquire(blocking=False):
        raise HTTPException(status_code=429, detail="Sunucu şu an meşgul, birkaç dakika sonra tekrar dene.")

    local_file = None
    try:
        gercek_url = uzun_linke_cevir(veri.link.strip())
        local_file = download_media(gercek_url)

        if not local_file:
            raise HTTPException(status_code=400, detail="Video indirilemedi")

        tarif = generate_recipe(local_file)
        return {"tarif": tarif}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        mesgul_kilidi.release()
        if local_file:
            try:
                os.remove(local_file)
            except Exception:
                pass


# --- FLUTTER WEB ARAYÜZÜNÜ SUN ---
# build/web içeriğini bu dosyanın yanındaki "static" klasörüne kopyalarsan
# site ana adreste (/) açılır. Mount en sona konmalı ki API yolları öncelikli olsun.
STATIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
if os.path.isdir(STATIC_DIR):
    app.mount("/", StaticFiles(directory=STATIC_DIR, html=True), name="static")


# --- KOMUT SATIRI MODU (eski yöntem, hâlâ çalışır) ---
if __name__ == "__main__":
    if len(sys.argv) > 1:
        video_url = uzun_linke_cevir(sys.argv[1])
    else:
        video_url = "https://www.youtube.com/shorts/ZvH-WuXus54"

    local_file = download_media(video_url)

    if local_file:
        try:
            recipe = generate_recipe(local_file)
        except Exception as e:
            recipe = f"HATA: {e}"
        print(base64.b64encode(recipe.encode("utf-8")).decode("utf-8"))
        try:
            os.remove(local_file)
        except Exception:
            pass
    else:
        print(base64.b64encode("HATA: Video indirilemedi.".encode("utf-8")).decode("utf-8"))