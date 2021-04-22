module Glush
  module ExprMatcher
    module_function

    def expr_matches?(expr, token, next_token = 0)
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
        expr_matches?(expr.left, token, next_token) || expr_matches?(expr.right, token, next_token)
      when Expr::Conj
        expr_matches?(expr.left, token, next_token) && expr_matches?(expr.right, token, next_token)
      when Expr::WithNext
        expr_matches?(expr.current_expr, token) && expr_matches?(expr.next_expr, next_token)
      else
        raise "unknown expr: #{expr.inspect}"
      end
    end
  end
end