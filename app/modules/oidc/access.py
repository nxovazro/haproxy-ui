from functools import wraps
from typing import Optional

from flask import jsonify

import app.modules.roxywi.common as roxywi_common


OIDC_ALLOWED_PLANS = frozenset({'company', 'cloud', 'support'})
OIDC_SUBSCRIPTION_ERROR = 'OIDC requires an active Company plan or higher'


def is_oidc_available(subscription: Optional[dict] = None) -> bool:
    if subscription is None:
        subscription = roxywi_common.return_user_subscription()

    try:
        is_active = int(subscription.get('user_status', 0)) == 1
    except (TypeError, ValueError):
        is_active = False

    plan = str(subscription.get('user_plan') or '').strip().lower()
    return is_active and plan in OIDC_ALLOWED_PLANS


def oidc_subscription_required(function):
    @wraps(function)
    def decorated_view(*args, **kwargs):
        if not is_oidc_available():
            return jsonify({
                'status': 'failed',
                'error': OIDC_SUBSCRIPTION_ERROR,
            }), 403
        return function(*args, **kwargs)

    return decorated_view
