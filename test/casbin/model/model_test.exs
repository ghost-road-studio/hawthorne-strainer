defmodule Casbin.ModelTest do
  use ExUnit.Case
  alias Casbin.Model

  @basic_rbac "test/support/basic_model.conf"

  describe "new" do
    test "creates a new empty model" do
      assert %Model{} = Model.new()
    end

    test "loads a model from disk" do
      assert %Model{
               request: %{"r" => "sub, obj, act"},
               policy: %{"p" => "sub, obj, act"},
               role: %{"g" => "_, _"},
               effect: %{"e" => "some(where (p.eft == allow))"},
               matchers: matchers
             } = Model.new(@basic_rbac)

      assert matchers["m"] =~ "g(r.sub, p.sub)"
    end
  end

  describe "new model from text" do
    test "creates a new model from text" do
      text = File.read!(@basic_rbac)

      assert %Model{
               request: %{"r" => "sub, obj, act"},
               policy: %{"p" => "sub, obj, act"},
               role: %{"g" => "_, _"},
               effect: %{"e" => "some(where (p.eft == allow))"},
               matchers: matchers
             } = Model.new_from_text(text)

      assert matchers["m"] =~ "g(r.sub, p.sub)"
    end
  end
end
