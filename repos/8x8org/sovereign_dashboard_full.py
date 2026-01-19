import os
#!/usr/bin/env python3
from apps.dashboard.server import main

if __name__ == "__main__":
    os.environ.setdefault('PORT', os.environ.get('PORT','5000'))

    main(host="0.0.0.0", port=int(os.environ.get("PORT","5000")))
