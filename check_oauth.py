#!/usr/bin/env python
import os
import sys
import django

# Add planpalapp to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'planpalapp'))

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'planpalapp.settings')
django.setup()

from oauth2_provider.models import Application

app = Application.objects.filter(client_id='UmrrG84UV5li86D7F5e9TDAOugedMLnrErUS1Cvj').first()
if app:
    print(f"✓ App Found!")
    print(f"  Name: {app.name}")
    print(f"  Client Type: {app.client_type}")
    print(f"  Grant Type: {app.authorization_grant_type}")
    print(f"  Redirect URIs: {app.redirect_uris}")
    print(f"  Skip Authorization: {app.skip_authorization}")
else:
    print("✗ App not found!")
