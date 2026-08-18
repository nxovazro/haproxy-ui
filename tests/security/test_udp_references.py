from types import SimpleNamespace

import pytest
from flask import g

from app.modules.db import ha_cluster as ha_cluster_sql
from app.modules.roxywi.exception import RoxywiResourceNotFound
from app.views.udp import views as udp_views


def _orphan_listener():
    return SimpleNamespace(
        id=2,
        name='DNS listener',
        desc='',
        cluster_id=999999,
        server_id=None,
        vip='192.0.2.53',
        port=53,
        config="[{'backend_ip': '10.0.0.176', 'port': 53, 'weight': 1}]",
        is_checker=0,
    )


@pytest.mark.security
def test_missing_ha_cluster_raises_clean_resource_error():
    with pytest.raises(RoxywiResourceNotFound) as exception:
        ha_cluster_sql.get_cluster(999999)

    assert str(exception.value) == 'HA cluster 999999 not found'
    assert 'SELECT' not in str(exception.value)


@pytest.mark.security
def test_udp_backend_status_returns_clear_orphan_reference_error_without_logging(app, monkeypatch):
    monkeypatch.setattr(udp_views.udp_sql, 'get_listener', lambda listener_id: _orphan_listener())
    monkeypatch.setattr(
        udp_views.ha_sql,
        'get_cluster',
        lambda cluster_id: (_ for _ in ()).throw(RoxywiResourceNotFound()),
    )
    monkeypatch.setattr(
        udp_views.roxywi_common,
        'handler_exceptions_for_json_data',
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError('expected reference errors must not be logged')),
    )

    with app.test_request_context('/udp/listener/2/10.0.0.176'):
        g.user_params = {'group_id': 1, 'role': 1, 'lang': 'en'}
        response, status = udp_views.UDPListenerBackendStatusView.get.__wrapped__(
            service='udp', listener_id=2, backend_ip='10.0.0.176'
        )

    assert status == 409
    assert response.get_json() == {
        'error': (
            'UDP listener 2 references HA cluster 999999, but it no longer exists. '
            'Edit the listener and select an existing resource, or delete the listener.'
        ),
        'status': 'failed',
    }


@pytest.mark.security
def test_udp_listener_page_shows_reference_warning_and_stops_status_polling(app, monkeypatch):
    monkeypatch.setattr(udp_views.udp_sql, 'get_listener', lambda listener_id: _orphan_listener())
    monkeypatch.setattr(udp_views.ha_sql, 'select_cluster', lambda cluster_id: [])

    with app.test_request_context('/udp/listener/2'):
        g.user_params = {'group_id': 1, 'role': 1, 'lang': 'en'}
        page = udp_views.UDPListener(False).get('udp', 2)

    assert 'UDP listener 2 references HA cluster 999999' in page
    assert 'udp-listener-invalid' in page
    assert 'udp-listener-reference-error' in page
    assert page.index('class="server-name"') < page.index('udp-listener-reference-error')
    assert "checkUdpBackendStatus('2'" not in page
    assert "checkStatus('2')" not in page


@pytest.mark.security
def test_udp_listener_api_returns_expected_reference_error_without_traceback(app, monkeypatch):
    monkeypatch.setattr(
        udp_views.udp_mod,
        'get_listener_config',
        lambda listener_id: {'id': listener_id, 'cluster_id': 999999, 'server_id': None},
    )
    monkeypatch.setattr(
        udp_views.udp_mod,
        'check_is_listener_active',
        lambda listener_id: (_ for _ in ()).throw(RoxywiResourceNotFound()),
    )
    monkeypatch.setattr(
        udp_views.roxywi_common,
        'handler_exceptions_for_json_data',
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError('expected reference errors must not be logged')),
    )

    with app.test_request_context('/api/udp/listener/2'):
        response, status = udp_views.UDPListener(True).get('udp', 2)

    assert status == 409
    assert 'references HA cluster 999999' in response.get_json()['error']
