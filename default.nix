{ buildPythonPackage
, flask
, pyyaml
}:

buildPythonPackage {
  name = "deploy";

  src = ./.;

  propagatedBuildInputs = [
    flask
    pyyaml
  ];
}
