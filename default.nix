{ buildPythonPackage
, flask
, pyyaml
}:

buildPythonPackage {
  name = "deploy_bot";

  src = ./.;

  propagatedBuildInputs = [
    flask
    pyyaml
  ];
}
