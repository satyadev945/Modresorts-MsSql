// External event listeners (CSP-compliant replacement for inline on* handlers)
(function () {
    'use strict';

    function bindEvents() {
        var citySelect = document.querySelector('.js-select');
        if (citySelect) {
            citySelect.addEventListener('change', function () {
                callRESTAPI();
            });
        }

        var reserveButton = document.querySelector('.js-reserve');
        if (reserveButton) {
            reserveButton.addEventListener('click', function () {
                confirmReservcation();
            });
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', bindEvents);
    } else {
        bindEvents();
    }
})();
