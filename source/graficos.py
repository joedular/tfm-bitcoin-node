# === Dependencias necesarias ===
# Antes de ejecutar, instalar con:
#   pip install pandas matplotlib


import os
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.cm as cm

# === CONFIGURACIÓN ===
RUTA_CSV = "/Users/jose/Desktop/TFM/bitcoin-monitor/" # Cambiar esta ruta
SALIDA = os.path.join(RUTA_CSV, "graficos")
RESUMEN_CSV = os.path.join(SALIDA, "resumen_estadistico.csv")
COMPARATIVA = os.path.join(SALIDA, "comparativas")
os.makedirs(SALIDA, exist_ok=True)
os.makedirs(COMPARATIVA, exist_ok=True)

# === FUNCIONES ===
def cargar_csv(filepath):
    sep = ";" if filepath.endswith(".csv") else ","
    try:
        df = pd.read_csv(filepath, sep=sep, engine="python", skip_blank_lines=True, on_bad_lines='skip')
        if "ciclo" in df.columns:
            df["tiempo_s"] = df["ciclo"].astype(int)
        else:
            print(f"[!] No se encontró 'ciclo' en {filepath}")
            return None
        return df
    except Exception as e:
        print(f"[!] Error al leer {filepath}: {e}")
        return None

def preparar_columna(df, col):
    df[col] = df[col].astype(str).str.replace(",", ".", regex=False)
    df[col] = pd.to_numeric(df[col], errors="coerce")
    return df

def graficar(df, col, titulo, ylabel, path_out):
    if col not in df.columns:
        print(f"[!] Columna no encontrada: {col}")
        return

    df = preparar_columna(df, col)
    df["media_movil"] = df[col].rolling(window=5, min_periods=1).mean()
    media = df[col].mean()

    plt.figure(figsize=(10, 5))
    plt.plot(df["tiempo_s"], df[col], marker="o", linestyle="-", color="steelblue", label="Valor original")
    plt.plot(df["tiempo_s"], df["media_movil"], color="orange", linestyle="--", label="Media móvil")
    plt.axhline(y=media, color='red', linestyle=':', label=f"Media: {media:.2f}")

    if col == "verificationprogress":
        plt.ylim(0, 1.05)

    plt.title(titulo)
    plt.xlabel("Tiempo (ciclo)")
    plt.ylabel(ylabel)
    plt.grid(True)
    plt.legend()
    plt.tight_layout()
    plt.savefig(path_out)
    plt.close()

def graficar_red(df, col, titulo, path_out, unidad="MB"):
    df = preparar_columna(df, col)

    # Diferencias entre lecturas sucesivas (descartar negativas por reinicios)
    df["delta"] = df[col].diff().clip(lower=0)

    if unidad == "MB":
        df["delta"] = df["delta"] / 1000
    elif unidad == "GB":
        df["delta"] = df["delta"] / 1e6

    media = df["delta"].mean()

    plt.figure(figsize=(10, 5))
    plt.plot(df["tiempo_s"], df["delta"], marker="o", linestyle="-", color="steelblue", label="Tráfico por intervalo")
    plt.axhline(y=media, color="red", linestyle=":", label=f"Media: {media:.2f} {unidad}")

    plt.title(titulo)
    plt.xlabel("Tiempo (ciclo)")
    plt.ylabel(f"Tráfico ({unidad})")
    plt.grid(True)
    plt.legend()
    plt.tight_layout()
    plt.savefig(path_out)
    plt.close()


def agregar_estadisticas(df, col, perfil, tipo, lista_resumen):
    df = preparar_columna(df, col)

    if col in ["net_rx_kB", "net_tx_kB"]:
        delta = df[col].max() - df[col].min()
        resumen = {
            "perfil": perfil,
            "tipo": tipo,
            "metrica": col,
            "media": delta,  # aquí el total de tráfico (en kB)
            "mediana": None,
            "std": None,
            "min": df[col].min(),
            "max": df[col].max(),
            "valores": df[col].count()
        }
    else:
        resumen = {
            "perfil": perfil,
            "tipo": tipo,
            "metrica": col,
            "media": df[col].mean(),
            "mediana": df[col].median(),
            "std": df[col].std(),
            "min": df[col].min(),
            "max": df[col].max(),
            "valores": df[col].count()
        }

    lista_resumen.append(resumen)


def procesar_archivo(filepath, lista_resumen):
    nombre = os.path.basename(filepath)
    df = cargar_csv(filepath)
    if df is None or df.empty:
        return

    tipo = "post" if "post_sync_metrics" in nombre else "sync"
    perfil = nombre.split("_")[3] if tipo == "post" else nombre.split("_")[2]
    carpeta = os.path.join(SALIDA, tipo, perfil)
    os.makedirs(carpeta, exist_ok=True)

    if tipo == "sync":
        columnas = [
            ("verificationprogress", "Progreso de sincronización", "%"),
            ("cpu_percent", "Uso de CPU", "%"),
            ("mem_percent", "Uso de RAM", "%"),
            ("disk_used_MB", "Uso de Disco", "MB"),
            ("net_rx_kB", "Red Entrante", "kB"),
            ("net_tx_kB", "Red Saliente", "kB")
        ]
    else:
        columnas = [
            ("cpu_percent", "Uso de CPU", "%"),
            ("mem_used_MB", "Memoria Usada", "MB"),
            ("disk_used_MB", "Disco Usado", "MB"),
            ("net_rx_kB", "Red Entrante", "kB"),
            ("net_tx_kB", "Red Saliente", "kB"),
            ("uptime_minutes", "Minutos Encendido", "minutos"),
            ("num_processes", "Nº de Procesos", "cantidad")
        ]

    for col, titulo, unidad in columnas:
        if col in df.columns:
            archivo_out = os.path.join(carpeta, f"{col}.png")
            if col in ["net_rx_kB", "net_tx_kB"]:
                graficar_red(df.copy(), col, f"{titulo} ({perfil})", archivo_out, unidad="MB")
            else:
                graficar(df.copy(), col, f"{titulo} ({perfil})", f"{titulo} ({unidad})", archivo_out)
            agregar_estadisticas(df.copy(), col, perfil, tipo, lista_resumen)


def graficar_comparativo(resumen_df, metrica, tipo):
    df_metrica = resumen_df[(resumen_df["metrica"] == metrica) & (resumen_df["tipo"] == tipo)]
    if df_metrica.empty:
        return

    plt.figure(figsize=(10, 5))
    perfiles = df_metrica["perfil"].unique()
    colores = plt.get_cmap("tab10")

    for idx, perfil in enumerate(perfiles):
        valores = df_metrica[df_metrica["perfil"] == perfil]
        media = valores["media"].values[0]
        plt.bar(perfil, media, color=colores(idx), label=f"{perfil}")

    plt.title(f"Comparativa de {metrica} ({tipo})")
    plt.ylabel(metrica)
    plt.tight_layout()
    nombre_out = f"comparativa_{tipo}_{metrica}.png"
    plt.savefig(os.path.join(COMPARATIVA, nombre_out))
    plt.close()

# === EJECUCIÓN PRINCIPAL ===
resumen_total = []
for archivo in os.listdir(RUTA_CSV):
    if archivo.endswith(".csv") and ("sync_log" in archivo or "post_sync_metrics" in archivo):
        procesar_archivo(os.path.join(RUTA_CSV, archivo), resumen_total)

# Crear DataFrame con los resultados
df_resumen = pd.DataFrame(resumen_total)

# Guardar resumen estadístico general
df_resumen.to_csv(RESUMEN_CSV, index=False, sep=";")

# Comparativas por tipo y métrica
if not df_resumen.empty:
    top_metricas = df_resumen["metrica"].unique()
    for tipo in ["sync", "post"]:
        for metrica in top_metricas:
            graficar_comparativo(df_resumen, metrica, tipo)

    # Guardar tabla comparativa por tipo
    tabla_comparativa = df_resumen.pivot_table(
        index=["perfil"], columns=["tipo", "metrica"], values="media"
    )
    tabla_comparativa.to_csv(os.path.join(COMPARATIVA, "tabla_comparativa.csv"), sep=";")

    # Guardar resumen completo (para anexos)
    df_resumen.to_csv(os.path.join(COMPARATIVA, "resumen_completo.csv"), index=False, sep=";")

    # Agregar CSV de estadísticas globales
    df_global = (
        df_resumen.groupby(["tipo", "metrica"])
        .agg({"media": "mean", "std": "mean", "min": "min", "max": "max"})
        .reset_index()
    )
    df_global.to_csv(os.path.join(COMPARATIVA, "estadisticas_globales.csv"), index=False, sep=";")

print("[✔] Todos los gráficos y CSV fueron generados correctamente.")
