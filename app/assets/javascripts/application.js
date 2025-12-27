// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or vendor/assets/javascripts of plugins, if any, can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file.
//
// Read Sprockets README (https://github.com/sstephenson/sprockets#sprockets-directives) for details
// about supported directives.
//
//= require jquery
//= require jquery_ujs
//= require_tree ./vendor
//= require custom/pjax-setup
//= require turbolinks
//= require cocoon
//= require custom/box
//= require custom/offcanvas
//= require custom/tree-menu

function getCookie(name) {
	const value = `; ${document.cookie}`;
	const parts = value.split(`; ${name}=`);
	if (parts.length === 2) return parts.pop().split(';').shift();
}

function setCookie(name, value) {
	document.cookie = name + "=" + (value || "");
}


document.addEventListener('DOMContentLoaded', function () {
	if ($("#status-filter")) {
		$("#status-filter").change(function () {
			let e = document.getElementById("status-filter");
			let value = $(this).val();
			setCookie("status", value)
			window.location.reload()
		});
	}

	const form = document.getElementById('make-transfer');
	const submitButton = document.getElementById('submit-button');
		submitButton && submitButton.addEventListener('click', function (event) {
			let inputs = document.querySelectorAll('input[type="text"]');  // Adjust this selector if necessary
			let count = 0;  // To count inputs with values
			let sum = 0;    // To sum the values

			inputs.forEach(function (input) {
				if (input.value) {  // Check if the input field has a value
					count++;  // Increment count if there is a value
					sum += parseFloat(input.value) || 0;  // Add the value to sum, ensure it's a number
				}
			});
			const confirmed = confirm(`Are you sure you want to sent ${sum} usd to ${count} users?`);

			if (!confirmed) {
				event.preventDefault(); // Prevent form submission if user cancels
			}
		});
});