//= require active_admin/base
//= require tinymce
//= require chartkick
//= require Chart.bundle

$(document).ready(function() {
  tinyMCE.init({
     mode: 'textareas',
     plugins: [
            'advlist autolink lists link image charmap print preview anchor',
            'searchreplace visualblocks code fullscreen',
            'insertdatetime media table contextmenu paste code'
        ]
   });
});