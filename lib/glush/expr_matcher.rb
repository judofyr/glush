module Glush
  module ExprMatcher
    module_function

    def expr_matches?(expr, token)
      case expr
      when Expr::Any
        true
      when Expr::Final
        false
      when Expr::Equal
        token == expr.token
      when Expr::Less
        token < expr.token
      when Expr::Greater
        token > expr.token
      when Expr::Alt
        expr_matches?(expr.left, token) || expr_matches?(expr.right, token)
      when Expr::Conj
        expr_matches?(expr.left, token) && expr_matches?(expr.right, token)
      else
        raise "unknown expr: #{expr.inspect}"
      end
    end
  end
end