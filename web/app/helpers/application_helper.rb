module ApplicationHelper
  # Header nav item: an icon (an emoji, or a picture under app/assets/images/icons/) and its label;
  # the icon is hidden from screen readers
  def nav_label(icon, label)
    mark = icon.end_with?(".png") ? image_tag("icons/#{icon}", alt: "", class: "h-5 w-5 object-contain") : tag.span(icon, "aria-hidden": "true")
    safe_join([ mark, tag.span(label) ])
  end

  # Cancel next to a form's Save: a light amber press button with a ✕ (dark mode dims it like every
  # press button)
  def cancel_link(path, label = t("records.form.cancel"))
    link_to path, class: "btn-press inline-flex items-center gap-1.5 rounded-xl bg-amber-100 text-amber-900 px-3.5 py-2 font-medium" do
      safe_join([ tag.svg(tag.path(d: "M6 6l12 12M18 6L6 18"), class: "h-4 w-4", viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
                          "stroke-width": "2.6", "stroke-linecap": "round", "aria-hidden": "true"), tag.span(label) ])
    end
  end

  # A page title with its picture in front (Pending, Records, Dashboard, My Account, the guide, the Edit, New Recurring Bill and Mark Paid pages,
  # the inbox, Sign in)
  def page_title(icon, title)
    tag.h1(class: "flex justify-center items-center gap-3 text-3xl font-bold") do
      safe_join([ image_tag("icons/#{icon}", alt: "", class: "h-10 w-10 object-contain"), tag.span(title) ])
    end
  end

  # The theme picked in the header menu (cookie), light by default
  def current_theme = ThemesController::THEMES.include?(cookies[:theme]) ? cookies[:theme] : "light"
end
