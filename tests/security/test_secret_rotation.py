import uuid

import pytest
from cryptography.fernet import Fernet

from app.modules.db.db_model import Cred, OidcProvider
from rotate_credential_secret import _fernet_from_environment, rotate_credentials


@pytest.mark.security
def test_credential_rotation_reencrypts_secret_fields_atomically(monkeypatch):
    old_key = Fernet.generate_key()
    new_key = Fernet.generate_key()
    old_fernet = Fernet(old_key)
    password = old_fernet.encrypt(b'secret-password').decode('ascii')
    credential = Cred.create(
        name=f'rotation-{uuid.uuid4().hex}', username='root', password=password, group_id=1,
        passphrase=None, private_key=None
    )
    provider = OidcProvider.create(
        slug=f'rotation-{uuid.uuid4().hex}',
        label='Rotation test',
        client_id='roxy-wi',
        client_secret_encrypted=old_fernet.encrypt(b'oidc-client-secret').decode('ascii'),
        enabled=0,
    )
    monkeypatch.setenv('ROXYWI_OLD_SECRET_PHRASE', old_key.decode('ascii'))
    monkeypatch.setenv('ROXYWI_SECRET_PHRASE', new_key.decode('ascii'))

    try:
        assert rotate_credentials() >= 2

        credential = Cred.get_by_id(credential.id)
        provider = OidcProvider.get_by_id(provider.id)
        assert Fernet(new_key).decrypt(credential.password.encode('ascii')) == b'secret-password'
        assert Fernet(new_key).decrypt(provider.client_secret_encrypted.encode('ascii')) == b'oidc-client-secret'
    finally:
        Cred.delete().where(Cred.id == credential.id).execute()
        OidcProvider.delete().where(OidcProvider.id == provider.id).execute()


@pytest.mark.security
def test_rotation_accepts_any_valid_non_placeholder_key(monkeypatch):
    valid_key = '_B8avTpFFL19M8P9VyTiX42NyeyUaneV26kyftB2E_4='
    monkeypatch.setenv('ROXYWI_SECRET_PHRASE', valid_key)

    assert isinstance(
        _fernet_from_environment('ROXYWI_SECRET_PHRASE'),
        Fernet,
    )


@pytest.mark.security
def test_rotation_rejects_change_me(monkeypatch):
    monkeypatch.setenv('ROXYWI_SECRET_PHRASE', 'CHANGE_ME')

    with pytest.raises(RuntimeError, match='must not be CHANGE_ME'):
        _fernet_from_environment('ROXYWI_SECRET_PHRASE')
