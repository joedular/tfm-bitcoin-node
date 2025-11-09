# Automatización y Monitorización de Nodos Bitcoin Core

Este repositorio contiene el código fuente, scripts y datos asociados al Trabajo Fin de Máster (TFM) titulado:

**“Automatización de la instalación y monitorización de nodos Bitcoin Core para diferentes perfiles de usuario”**  
Universidad de Valladolid (UVA) — Máster en Ingeniería Informática  
Autor: **José Ulloa Araya**  
Año: **2025**

---

## 📘 Descripción general

El proyecto desarrolla un sistema completo para la **automatización, configuración y monitorización de nodos Bitcoin Core** en entornos GNU/Linux.  
Permite desplegar un nodo según distintos **perfiles funcionales**, registrar métricas de rendimiento y generar análisis comparativos reproducibles.

El código está organizado en dos componentes principales:

1. **`script_tfm.sh`**  
   Script principal en **Bash** que automatiza la instalación, configuración y monitorización de Bitcoin Core.
2. **`graficos.py`**  
   Módulo en **Python** que procesa los logs CSV generados por el script y produce tablas y gráficas comparativas.

---

## ⚙️ Funcionalidades principales

- Instalación automatizada de **Bitcoin Core** desde código fuente.  
- Creación automática del archivo `bitcoin.conf` según el perfil seleccionado.  
- Registro de métricas de **CPU, RAM, disco, red y progreso de verificación**.  
- Almacenamiento de métricas en formato CSV en `/var/log/bitcoind-monitor/`.  
- Procesamiento y generación de gráficas comparativas mediante `graficos.py`.  
- Soporte para los siguientes **perfiles de usuario**:

| Perfil | Descripción |
|--------|--------------|
| **Validador** | Nodo completo destinado a validación y consenso. |
| **Analista** | Nodo orientado al estudio de métricas y rendimiento. |
| **dApps Developer** | Nodo ligero para desarrollo de aplicaciones descentralizadas. |
| **Lightning Operator** | Nodo preparado para operar en la red Lightning. |
| **Educador** | Nodo optimizado para entornos docentes y demostrativos. |
| **Estándar** | Configuración general equilibrada. |

---

## 🧰 Requisitos del sistema

- Sistema operativo: **GNU/Linux (Ubuntu 22.04+ o Debian 12+)**
- Dependencias:
  - `git`, `curl`, `python3`, `pip`, `gnuplot`, `psutil`
- Espacio en disco recomendado: **250 GB**
- RAM mínima: **4 GB**

---

## 🚀 Instalación y uso

### 1. Clonar el repositorio
```bash
git clone https://github.com/joedular/tfm-bitcoin-node.git
cd tfm-bitcoin-node/source
sudo ./script_tfm.sh
