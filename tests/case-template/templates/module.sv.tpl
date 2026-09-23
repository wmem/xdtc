module {{ name }} #(
{% for i, p in ipairs(params) do %}
    parameter {{ p.name }} = {{ p.value }}{% if i < #params then %},{% end %}
{% end %}
);

{* body *}
endmodule
