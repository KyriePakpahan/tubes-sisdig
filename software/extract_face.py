import os
import cv2
import numpy as np
from numpy.linalg import norm

# ===== Get script directory for model paths =====
_script_dir = os.path.dirname(os.path.abspath(__file__))

# ===== Load ArcFace model =====
_model_path = os.path.join(_script_dir, "arcface.onnx")
net = cv2.dnn.readNetFromONNX(_model_path)

# ===== GLOBAL REFERENCE EMBEDDING =====
ref_embedding = None  # akan diisi saat pemanggilan pertama
ref_file = os.path.join(_script_dir, "ref_embedding.npy")

# ===== Jika file referensi ada, baca dulu =====
if os.path.exists(ref_file):
    ref_embedding = np.load(ref_file)
    print("[INFO] Referensi embedding berhasil dimuat dari file")

def extract_face_binary(image_path, similarity_threshold=0.4):
    """
    Input  : path gambar wajah (contoh: 'face.jpg')
    Output : binary feature vector (numpy array, shape (512,)) dalam format hex
    """
    global ref_embedding

    # ===== Load image =====
    img = cv2.imread(image_path)
    if img is None:
        raise RuntimeError(f"Gambar '{image_path}' tidak terbaca")

    img_h, img_w = img.shape[:2]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # ===== Face detector =====
    detector = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    )

    faces = detector.detectMultiScale(gray, 1.1, 3)

    if len(faces) == 0:
        raise RuntimeError("Wajah tidak terdeteksi")

    # print(f"Jumlah wajah terdeteksi: {len(faces)}")

    debug_img = img.copy()
    embedding = None

    for i, (x, y, w, h) in enumerate(faces):
        area_ratio = (w * h) / (img_w * img_h)
        if area_ratio < 0.02:
            print(f"[WARNING] Face #{i} terlalu kecil, dilewati")
            continue

        # ===== Draw bounding box =====
        cv2.rectangle(debug_img, (x, y), (x+w, y+h), (0, 255, 0), 2)
        cv2.putText(
            debug_img, f"Face {i}", (x, y - 10),
            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2
        )

        # ===== Crop wajah =====
        face = img[y:y+h, x:x+w]

        # ===== VERIFIKASI VISUAL WAJAH =====
        # cv2.imshow("1️⃣ Detected Face (Crop Asli)", face)
        # cv2.waitKey(800)

        # ===== Preprocessing ArcFace =====
        face_pp = cv2.resize(face, (112, 112))
        face_pp = cv2.cvtColor(face_pp, cv2.COLOR_BGR2RGB)
        face_pp = face_pp.astype(np.float32) / 255.0
        face_pp = (face_pp - 0.5) / 0.5

        # ===== Pastikan masih terlihat wajah =====
        face_vis = ((face_pp + 1) / 2 * 255).astype(np.uint8)
        face_vis = cv2.cvtColor(face_vis, cv2.COLOR_RGB2BGR)
        # cv2.imshow("2️⃣ Face Setelah Preprocessing", face_vis)
        # cv2.waitKey(800)

        # ===== ArcFace inference =====
        blob = cv2.dnn.blobFromImage(face_pp)
        net.setInput(blob)
        embedding = net.forward()[0]

        norm_val = norm(embedding)
        # print(f"Face #{i} embedding norm: {norm_val:.4f}")
        # if not (0.8 < norm_val < 1.2):
        #     print("[WARNING] Embedding tidak stabil")
            

    # ===== Tampilkan bounding box di gambar asli =====
    cv2.imshow("3️⃣ Verifikasi Bounding Box (Gambar Asli)", debug_img)
    cv2.waitKey(0)
    cv2.destroyAllWindows()

    # print("\n===== FEATURE VECTOR MENTAH =====")
    # print(embedding)

    # ===== Tentukan embedding yang dipakai =====
    if ref_embedding is not None:
        cos_sim = np.dot(ref_embedding, embedding) / (norm(ref_embedding) * norm(embedding))
        # print(f"Cosine similarity dengan referensi: {cos_sim:.4f}")

        if cos_sim >= similarity_threshold:
            # print("Foto mirip dengan referensi → menggunakan feature vector lama")
            embedding_to_use = ref_embedding
        else:
            # print("Foto berbeda → menggunakan feature vector baru")
            embedding_to_use = embedding
            ref_embedding = embedding  # update referensi
            np.save(ref_file, ref_embedding)  # simpan ke file
            # print(f"[INFO] Embedding baru disimpan sebagai referensi di {ref_file}")
    else:
        # print("Belum ada referensi → menggunakan embedding baru")
        embedding_to_use = embedding
        ref_embedding = embedding
        np.save(ref_file, ref_embedding)
        # print(f"[INFO] Embedding disimpan sebagai referensi di {ref_file}")

    # ===== BINARIZATION =====
    binary_vector = (embedding_to_use >= 0).astype(np.uint8)

    # print("\n===== BINARIZATION RESULT =====")
    # print("Binary vector shape:", binary_vector.shape)
    # print("First 64 bits:", binary_vector[:64])

    binary_bytes = np.packbits(binary_vector)
    # print("\n===== PACKED BINARY =====")
    # print("Packed bytes length:", len(binary_bytes))
    # print("First 16 bytes:", binary_bytes[:16])

    # ===== Simpan hasil =====
    np.savetxt("face_binary_bits.txt", binary_vector, fmt="%d")
    binary_bytes.tofile("face_binary_bytes.bin")
    print("\n[OK] Feature vector dalam Hexadecimal berhasil disimpan")

    # binary_bytes = np.packbits(binary_vector)
    hex = binary_bytes.tobytes().hex()
    return hex




# ===== Contoh penggunaan =====
# h1 = extract_face_binary("face.jpg")
# h2 = extract_face_binary("face1.jpeg") #b1 dan b2 razaq


# print("H1 first 64 bytes:", h1[:64])
# print("H2 first 64 bytes:", h2[:64])


# if np.array_equal(h1, h2):
#     print("✅ B1 dan B2 identik (sama persis)")
# else:
#     print("❌ B1 dan B2 berbeda")



