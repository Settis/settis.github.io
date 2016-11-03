Jekyll::Hooks.register :posts, :pre_render do |post|
  //#post.data["pub_date"] = post.data["date"] if post.data["pub_date"] == {}
  post.data["pub_date"] = post.data.fetch("pub_date", post.data["date"])
end
