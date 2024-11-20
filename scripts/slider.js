function initComparisons() {
    var overlays = document.getElementsByClassName("img-comp-overlay");
    for (var i = 0; i < overlays.length; i++) {
        compareImages(overlays[i]);
    }

    function animateSlider(slider, overlay) {
        const overlayMovement = [
            { width: "0px" },
            { width: "50%" },
        ];

        const sliderMovement = [
            { left: "0" },
            { left: "50%" },
        ];

        const sliderTiming = {
            duration: 600,
            iterations: 1,
            easing: "ease-in-out",
        };
        let sliderAnim = slider.animate(sliderMovement, sliderTiming);
        sliderAnim.onfinish = (_) => {
            slider.style.left = "50%";
        };
        let overlayAnim = overlay.animate(overlayMovement, sliderTiming);
        overlayAnim.onfinish = (_) => {
            overlay.style.width = "50%";
        };
    }

    function compareImages(img) {
        var clicked = false;
        var w = img.parentElement.offsetWidth;
        var h = img.offsetHeight;

        img.style.width = (w / 2) + "px";

        var slider = document.createElement("div");
        slider.setAttribute("class", "img-comp-slider");

        img.parentElement.insertBefore(slider, img);

        slider.style.top = (h / 2) - (slider.offsetHeight / 2) + "px";
        slider.style.left = (w / 2) + "px";

        slider.addEventListener("mousedown", slideReady);
        window.addEventListener("mouseup", slideFinish);
        slider.addEventListener("touchstart", slideReady);
        window.addEventListener("touchend", slideFinish);

        function slideReady(e) {
            e.preventDefault();
            clicked = true;

            window.addEventListener("mousemove", slideMove);
            window.addEventListener("touchmove", slideMove);
        }

        function slideFinish() {
            clicked = false;
        }

        function slideMove(e) {
            if (!clicked)
                return false;

            var pos = getCursorPos(e)
            if (pos < 0) pos = 0;
            if (pos > w) pos = w;
            slide(pos);
        }

        function getCursorPos(e) {
            e = (e.changedTouches) ? e.changedTouches[0] : e;
            var rect = img.getBoundingClientRect();
            return e.pageX - rect.left;
        }

        function slide(x) {
            img.style.width = x + "px";
            slider.style.left = img.offsetWidth + "px";
        }

        animateSlider(slider, img)
    }
}