/*
 * External event listeners (CSP compliant - no inline on* handlers in HTML).
 * Enforced by Azure Front Door WAF / Content-Security-Policy response headers.
 */
(function () {
    'use strict';

    function bindHandlers() {
        var citySelect = document.querySelector('.js-select');
        if (citySelect) {
            citySelect.addEventListener('change', function () {
                callRESTAPI();
            });
        }

        var reserveButton = document.querySelector('.button--reserve');
        if (reserveButton) {
            reserveButton.addEventListener('click', function () {
                confirmReservcation();
            });
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', bindHandlers);
    } else {
        bindHandlers();
    }
})();
