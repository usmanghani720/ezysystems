(function ($) {
  $.turbo = {
    hasRun: false,
    execute: function (selector, callback) {
      $(document).ready(function () {
        if (!$.turbo.hasRun) {
          $(document).trigger("pjax:render");
          $.turbo.hasRun = true;
        }
      });

      $(document).on("pjax:render", function () {
        if ($(selector).length) callback();
      });
    },
  };
})(jQuery);

$(function () {
  $.pjax({
    link: "[data-pjax]",
    wait: 400,
    area: [".content-wrapper-inner"],
    load: {
      head: "meta, title",
      css: true,
      script: true,
    },
    cache: {
      click: true,
      submit: true,
      popstate: true,
      get: true,
      post: false,
    },
    scrollTop: false,
  });

  $(document).on("pjax:fetch", function () {
    $.turbo.hasRun = false;
  });

  // Transition
  var $transitionContainer = $(".content-wrapper-transition");
  var $pageLoader = $(".page-loader");

  $(document).bind("pjax:fetch", function () {
    $("body").animate(
      {
        scrollTop: 0,
      },
      {
        queue: false,
        duration: 300,
      }
    );

    $pageLoader.fadeIn();

    $transitionContainer.animate(
      {
        top: 100,
        opacity: 0,
      },
      {
        queue: false,
        duration: 400,
      }
    );
  });

  $(document).bind("pjax:render", function () {
    if (window.location.href.includes("word_type")) {
      let check_value = window.location.href.split("=")[1];
      let list = document.getElementById("word-filter").options;
      if (list) {
        for (let i = 0; i < list.length; i++) {
          if (list[i].value == check_value) {
            list[i].selected = true;
          }
        }
      }
    }
    $("#word-filter").change(function () {
      let e = document.getElementById("word-filter");
      let filter_value = $(this).val();
      $.ajax({
        url: "/admin/dictionaries",
        type: "GET",
        dataType: "json",
        data: { type: filter_value },
        success: function (response) {
          let value_selected =
            document.getElementById("word-filter").options[
              document.getElementById("word-filter").selectedIndex
            ].value;
          window.location.href =
            "/admin/dictionaries?word_type=" + value_selected;
          //window.location.reload();
        },
      });
    });
    $("#bulk-operation").change(function () {
      let selected_ids = [];
      let e = document.getElementById("bulk-operation");
      let action_value = $(this).val();
      $("input:checkbox:checked").each(function () {
        selected_ids.push($(this)[0].id);
      });
      if (selected_ids.length > 0) {
        $.ajax({
          url: "/admin/dictionaries/bulk_operate",
          type: "POST",
          dataType: "json",
          data: { ids: selected_ids, action_value: action_value },
          success: function (response) {
            window.location.reload();
          },
        });
      }
    });
    $("body").tooltip({
      selector: "[data-toggle='tooltip']",
    });

    $("body").popover({
      selector: "[data-toggle='popover']",
    });

    AOS.init({
      offset: 100,
      once: true,
    });

    // Topbar dropdown custom scrollbar
    $(".navbar .menu")
      .slimscroll({
        height: "200px",
        alwaysVisible: false,
        size: "3px",
      })
      .css("width", "100%");

    // Theme Customization
    $(".color-scheme-picker > li").on("click", function (e) {
      e.preventDefault();
      var $this = $(this);
      var availableColors =
        "skin-deep-blue skin-pale-green skin-deep-purple skin-deep-orange skin-blue-grey";

      $("body").removeClass(availableColors).addClass($this.data("color"));

      $("#customizationModal").modal("hide");
    });

    $(".sidebar-image-picker > li").on("click", function (e) {
      e.preventDefault();
      var $this = $(this);
      var availableImages =
        "rocky-beach dark-waves starry misty-mountains sunrise starry-mountains";

      $("body").removeClass(availableImages).addClass($this.data("image"));

      $("#customizationModal").modal("hide");
    });

    // Sidebar custom scrollbar
    if (!$("body").hasClass("fixed")) {
      if (typeof $.fn.slimScroll != "undefined") {
        $(".sidebar").slimScroll({ destroy: true }).height("auto");
      }
    } else {
      $(window)
        .on("resize", function () {
          $(".sidebar").slimScroll({ destroy: true }).height("auto");
          $(".sidebar").slimscroll({
            height: $(window).height() - $(".main-header").height() + "px",
            color: "rgba(255, 255, 255,0.4)",
            size: "3px",
          });
        })
        .trigger("resize");
    }

    $('input[type="radio"]').on("click change", function (e) {
      if ($(this).val() === "image") {
        document.getElementById("ad_url").classList.remove("hide");
        document.getElementById("ad_link").classList.remove("hide");
        if (document.getElementById("ad_code")){
          document.getElementById("ad_code").classList.add("hide");
        }
      } else if ($(this).val() === "javascript") {
        if (document.getElementById("ad_code")){
          document.getElementById("ad_code").classList.remove("hide");
        }
        document.getElementById("ad_url").classList.add("hide");
        document.getElementById("ad_link").classList.add("hide");
      }
    });
    $pageLoader.fadeOut(function () {
      $transitionContainer.animate(
        {
          top: 0,
          opacity: 1,
        },
        {
          queue: false,
          duration: 400,
        },
        function () {
          $(document).trigger("pjax:transitionComplete");
        }
      );
    });
  });
});
