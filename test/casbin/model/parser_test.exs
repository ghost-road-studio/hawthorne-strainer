defmodule Casbin.Model.ParserTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  alias Casbin.Model.Parser
  alias Casbin.Model

  @basic_rbac "test/support/basic_model.conf"

  describe "parse_file/1" do
    test "correctly parses the file from disk" do
      assert %Model{
               request: %{"r" => "sub, obj, act"},
               policy: %{"p" => "sub, obj, act"},
               role: %{"g" => "_, _"},
               effect: %{"e" => "some(where (p.eft == allow))"},
               matchers: matchers
             } = Parser.parse_file(@basic_rbac)

      assert matchers["m"] =~ "g(r.sub, p.sub)"
    end

    test "raises File.Error if file not found" do
      assert_raise File.Error, fn ->
        Parser.parse_file("bogus.conf")
      end
    end
  end

  describe "parse_text/1" do
    test "correctly parses a standard RBAC model string" do
      %Model{
        request: %{"r" => "sub, obj, act"},
        policy: %{"p" => "sub, obj, act"},
        role: %{"g" => "_, _"},
        effect: %{"e" => "some(where (p.eft == allow))"},
        matchers: matchers
      } = File.read!(@basic_rbac) |> Parser.parse_text()

      assert matchers["m"] == "g(r.sub, p.sub) && r.obj == p.obj && r.act == p.act"
    end

    test "ignores comments and empty lines" do
      text = """
      # This is a comment
      [request_definition]

      r = sub, obj, act
      # Hello world
      """

      assert %Model{request: request} = Parser.parse_text(text)
      assert request["r"] == "sub, obj, act"
    end

    test "handles multiple keys in one section (e.g., g, g2)" do
      text = """
      [role_definition]
      g = _, _
      g2 = _, _, _
      """

      assert %Model{role: roles} = Parser.parse_text(text)
      assert roles["g"] == "_, _"
      assert roles["g2"] == "_, _, _"
    end

    test "logs warning for invalid lines" do
      text = """
      [request_definition]
      r = sub, obj, act
      this_line_is_invalid_no_equals_sign
      """

      assert capture_log(fn ->
               model = Parser.parse_text(text)
               # Ensure the valid part was still parsed
               assert model.request["r"] == "sub, obj, act"
             end) =~
               ~s([warning] [Casbin.Model.Parser] Skipping invalid line: "this_line_is_invalid_no_equals_sign")
    end

    test "ignores unknown sections" do
      text = """
      [unknown_definition]
      x = y
      """

      assert %Model{} = Parser.parse_text(text)
    end
  end
end
