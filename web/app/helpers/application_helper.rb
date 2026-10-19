module ApplicationHelper
  # Header nav item: an icon (an emoji, or a picture under app/assets/images/icons/) and its label;
  # the icon is hidden from screen readers
  def nav_label(icon, label)
    mark = icon.end_with?(".png") ? image_tag("icons/#{icon}", alt: "", class: "h-5 w-5 object-contain") : tag.span(icon, "aria-hidden": "true")
    safe_join([ mark, tag.span(label) ])
  end

  # A page title with its picture in front (Upcoming, Records, Dashboard, My Account, the guide,
  # the inbox, Sign in)
  def page_title(icon, title)
    tag.h1(class: "flex items-center gap-3 text-3xl font-bold") do
      safe_join([ image_tag("icons/#{icon}", alt: "", class: "h-10 w-10 object-contain"), tag.span(title) ])
    end
  end
end
