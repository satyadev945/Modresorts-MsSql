// External event listeners (replaces inline onchange/onclick handlers for CSP compliance)
document.addEventListener('DOMContentLoaded', function () {
    var citySelect = document.getElementById('city-select');
    if (citySelect) {
        citySelect.addEventListener('change', function () {
            callRESTAPI();
        });
    }
    var reserveButton = document.getElementById('reserve-button');
    if (reserveButton) {
        reserveButton.addEventListener('click', function () {
            confirmReservcation();
        });
    }
});
