"""
WSGI para colar no PythonAnywhere (Web → WSGI configuration file).

Opção A — importar este ficheiro (ajuste o caminho para o seu clone):
    import sys
    sys.path.insert(0, "/home/SEU_USER/APP-Biblia-Inteligente/backend")
    from pythonanywhere_wsgi import application

Opção B — copiar o conteúdo abaixo para o ficheiro WSGI do PA (substitua BACKEND_DIR).
"""
import os
import sys

# Pasta onde está manage.py e o pacote `config/` (normalmente .../APP-Biblia-Inteligente/backend)
BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

from django.core.wsgi import get_wsgi_application

application = get_wsgi_application()
