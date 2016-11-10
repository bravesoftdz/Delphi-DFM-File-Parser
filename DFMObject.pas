unit DFMObject;

//author: Alexander A. Chaker
//date:   2/16/2016
//Description: object that parses a DFM file and manipulates it

//Version: 0.4
  //Changelog: -Fixed parsing nested itemgroups
//Version: 0.5 (3/8/2016)
  //Changelog: -Add function retrieveObject to search for child objects
//Version: 0.6 (3/15/2016)
  //Changelog: -Correct Destroy procedures, fixes memory leaks
//Version: 0.7 (3/16/2016)
  //Changelog: -Fixing more memory leaks
//Version: 0.8 (3/29/2016)
  //Changelog: -Add condition when object doesn't have a name
//Version: 0.9 (4/15/2016)
  //Changelog: -Fix parsing where attributes' names contains 'object*' or '*end'
//Version: 1.0 (4/21/2016)
  //Changelog: -Add fFilePath private variable

interface

uses System.SysUtils, System.Variants, System.Classes, System.RegularExpressions, DBXJSON, DBXJSONReflect, system.JSON;

function identifyAttribute(s: TStringList; lineNbr: Integer): integer; //returns the type of the attribute
function isAttribute(s: TStringList; lineNbr: Integer): boolean; //returns true if the line is an attribute format " attributename = ..."

type
  TDFMObject = class;
  TDFMItem = class;
  TDFMItemGrp = class;
  TArrayDFMObject = array of TDFMObject;
  TArrayItemGrp = array of TDFMItemGrp;
  TArrayDFMItem = array of TDFMItem;

  TDFMObject = class(TObject)
  private
    fname: string; //DFM object name
    fObjType: string; //DFM object type
    fAttr: TStringList; //body of the DFM object
    fArrayDFMObj: TArrayDFMObject; //group of child DFM objects
    fArrayDFMObjCnt: integer; //count of array objects to manage array length
    fArrayItemGrp: TArrayItemGrp; //group of items
    fArrayItemGrpCnt: integer; //count of item groups
    fFilePath: string; //dir of the DFM object

    function getName: string;
    function getObjType: string;
    function getAttr: TStringList;
    function getArrayDFMObjCnt: Integer;
    function getArrayItemGrpCnt: integer;
    function getArrayItemGrp: TArrayItemGrp;
    function getArrayDFMObject: TArrayDFMObject;
    function getFilePath: string;
    //
    procedure setName(n: string);
    procedure setObjType(t: string);
    procedure setAttr(a: TStringList);
    procedure setFilePath(d: string);
    //

  public
    constructor Create; overload;
    constructor Create(DFMFilePath: string); overload; //loads and parses the file.dfm
    destructor Destroy; override;
    //
    function Parse(s: TStringList; begn: Integer): integer; //parses a StringList; begn param is which line parsing starts(used when Parsing with recursion)
    function ToString: string; override; //prints the DFMObject based on the Delphi structure
    function retrieveAttributeValue(attrName: string): string; // returns the value of the attribute name
    function retrieveObject(componentName: string): TDFMObject; // returns the child object based on component, nil if object not found
    function removeAttribute(name: string): integer; // removes the line of the attribute name, returns number of lines deleted
    function retrieveAttrLineNbr(name: string): integer; //returns line number of attribute specified
    //
    procedure assignAttribute(name: string; value: string); // replaces value with the parameter
    procedure insertChildObj(obj: TDFMObject); //insert child DFM object into the array
    procedure insertItemGrp(g: TDFMItemGrp); //insert item group
    procedure removeItemGrp(name: string); // remove item group based on its name
    //
    property name: string read getName write setName; //name of the DFM object, used in the header
    property objType: string read getObjType write setObjType; //type of the DFM object, used in the header
    property Attr: tstringlist read getAttr write setAttr;	//list of a component 
    property ArrayDFMObjCnt: Integer read getArrayDFMObjCnt; //count of child DFM objects
    property ArrayItemGrpCnt: integer read getArrayItemGrpCnt; //count of itemGroups
    property ArrayItemGrp: TArrayItemGrp read getArrayItemGrp; //array of itemGroups
    property ArrayDFMObject: TArrayDFMObject read getArrayDFMObject; //array of child DFMObjects
    property filePath: string read getFilePath write setFilePath; //file path of the parsed DMF file

  end;

  TDFMItemGrp = class(TObject)
  private
    fArrayItems: TArrayDFMItem;
    fArrayItemsCnt: Integer;
    fName: string;
    function getName: string;
    function getArrayItemsCnt: Integer;
    function getArrayDFMItem: TArrayDFMItem;

    procedure setName(n: string);
  public
    constructor Create;
    destructor Destroy; override;

    procedure insertItem(i: TDFMItem);

    function ToString: string; override;
    function Parse(s: TStringList; begn: Integer): integer;

    property name: string read getName write setName;
    property ArrayItemsCnt: integer read getArrayItemsCnt;
    property ArrayDFMItem: TArrayDFMItem read getArrayDFMItem;
  end;

  TDFMItem = class(TDFMObject)
  public
    constructor Create;
    destructor Destroy; override;
    function ToString: string; override;
  end;

implementation

{ TDFMObject }

function TDFMObject.getName: string;
begin
  result := fname;
end;

procedure TDFMObject.assignAttribute(name: string; value: string);
var
  index: integer;

begin
  index := 0;
  while index <> (Attr.Count) do
  begin
    if TrimLeft(Attr.Strings[index]).StartsWith(name, True) then
    begin
      Attr.Strings[index] := Attr.Strings[index].Substring(0, Attr.Strings[index].IndexOf('=') + 1)
        + ' ' + value;
      break;
    end;
    inc(index);
  end;
end;

constructor TDFMObject.Create;
begin
  inherited;
  fAttr := TStringList.Create;
  setLength(fArrayDFMObj, 10);
  setLength(fArrayItemGrp, 10);
end;

constructor TDFMObject.Create(DFMFilePath: string);
var
  tmpStringlist: TStringList;
begin
  tmpStringlist := TStringList.Create;

  try
    Self.Create();
    //
    tmpStringlist.LoadFromFile(DFMFilePath);
    Self.Parse(tmpStringList, 0);
  finally
    FreeandNil(tmpStringList);
  end;
end;

destructor TDFMObject.destroy;
var
  i: integer;
begin
  FreeAndNil(fAttr);

  for i := low(fArrayDFMObj) to fArrayDFMObjCnt - 1 do
    FreeAndNil(fArrayDFMObj[i]);

  for i := low(fArrayItemGrp) to fArrayItemGrpCnt - 1 do
    FreeAndNil(fArrayItemGrp[i]);

  inherited;
end;

function TDFMObject.getArrayDFMObjCnt: Integer;
begin
  result := fArrayDFMObjCnt;
end;

function TDFMObject.getArrayDFMObject: TArrayDFMObject;
begin
  result := fArrayDFMObj;
end;

function TDFMObject.getArrayItemGrp: TArrayItemGrp;
begin
  result := fArrayItemGrp;
end;

function TDFMObject.getArrayItemGrpCnt: integer;
begin
  result := fArrayItemGrpCnt;
end;

function TDFMObject.getAttr: TStringList;
begin
  result := fAttr;
end;

function TDFMObject.getFilePath: string;
begin
  result := fFilePath;
end;

function TDFMObject.getObjType: string;
begin
  result := fObjType;
end;

//returns 1 when line is an attribute of format "attr = < ... >"
//        2 when line is an attribute of format "attr = (' ... ')"
//        3 when line is an attribute of format "attr = [ ... ]"
//        4 when line is an attribute of format "attr = { ... }"
//        5 when line is an attribute of format "attr = ' ... '"

function identifyAttribute(s: TStringList; lineNbr: integer): integer;
var
  line: string;
  LineIndex: integer;
  i: integer;
begin
  LineIndex := lineNbr;

  result := 0;
  line := s.Strings[LineIndex];

  if not line.Contains('=') then
    exit
  else
  begin
    if trim(line).EndsWith('=') then //when attribute value is on the next line
    begin
      inc(lineindex);
      while (lineindex <> s.Count) and (trim(s.Strings[LineIndex]).Equals('')) do
        inc(lineindex);
      line := line + s.Strings[LineIndex];
    end;
  end;

  for i := 1 to 32 do
    line := StringReplace(line, chr(i), '', [rfReplaceAll]); //remove control charaters (white spaces)

  if line.Chars[line.IndexOf('=') + 1] = '<' then
    result := 1
  else if line.Chars[line.IndexOf('=') + 1] = '(' then
    result := 2
  else if line.Chars[line.IndexOf('=') + 1] = '[' then
    result := 3
  else if line.Chars[line.IndexOf('=') + 1] = '{' then
    result := 4
  else if line.Chars[line.IndexOf('=') + 1] = '''' then
    result := 5;

end;

//takes into consideration the attributes that has a "." in their name

function isAttribute(s: TStringList; lineNbr: integer): Boolean;
var
  line: string;
begin
  result := False;
  line := s.Strings[lineNbr];

  if TRegEx.IsMatch(trimleft(line), '^[A-z0-9]+[.]?[A-z0-9]*[ ]*=') then
    result := True;
end;

procedure TDFMObject.insertChildObj(obj: TDFMObject);
begin
  fArrayDFMObj[fArrayDFMObjCnt] := obj;
  inc(fArrayDFMObjCnt);

  if fArrayDFMObjCnt = length(fArrayDFMObj) then
    setlength(fArrayDFMObj, length(fArrayDFMObj) * 2);
end;

procedure TDFMObject.insertItemGrp(g: TDFMItemGrp);
begin
  fArrayItemGrp[fArrayItemGrpCnt] := g;
  inc(fArrayItemGrpCnt);

  if fArrayItemGrpCnt = length(fArrayItemGrp) then
    setlength(fArrayItemGrp, length(fArrayItemGrp) * 2);
end;

function TDFMObject.Parse(s: TStringList; begn: Integer): integer;
var
  index: Integer;
  tmpStringList: TStringList;
  line: string;
  LastIndex: integer;

begin
  tmpStringList := TStringList.Create;
  try
    try
      index := begn;

      line := s.Strings[index];

      //set object name and type
      //object header has format "object name: objecttype"
      if line.Contains(':') then
      begin
        self.name := TrimLeft(line).Substring(TrimLeft(line).IndexOf(' ', 0) + 1,
          TrimLeft(line).IndexOf(':', 0) - TrimLeft(line).IndexOf(' ', 0) - 1);
        self.objType := TrimLeft(line).Substring(TrimLeft(line).IndexOf(':', 0) + 1,
          TrimLeft(line).Length - TrimLeft(line).IndexOf(':', 0));
      end
      else //if object doesn't have a name, and header has a format "object objecttype"
      begin
        self.objType := TrimLeft(line).Substring(TrimLeft(line).IndexOf(' ', 0) + 1,
          TrimLeft(line).Length - TrimLeft(line).IndexOf(' ', 0));
      end;

      self.name := trim(self.name);
      self.objType := trim(self.objType);

      inc(index); //start parsing after the object header
      line := s.Strings[index];

      while (index <> s.Count) and ((not trimRight(line).EndsWith(' end', True)) and not (trimRight(line) = 'end')) do
      begin
		//if new child object
        if ((TrimLeft(line).StartsWith('object ', True)) or (TrimLeft(line) = 'object ')) then
        begin
          self.insertChildObj(TDFMObject.Create);
          lastIndex := self.fArrayDFMObj[fArrayDFMObjCnt - 1].Parse(s, index);
          index := lastIndex + 1;
        end
		//if itemGroup
        else if identifyAttribute(s, index) = 1 then // identify if groupitem attribute with format " attr = <  [items] ...> "
        begin
          self.insertItemGrp(TDFMItemGrp.Create);
          lastIndex := self.fArrayItemGrp[fArrayItemGrpCnt - 1].Parse(s, index);
          index := lastIndex + 1;
        end
        else
		//if DFM component attribute
        begin
          tmpStringList.Append(line);
          inc(index);
        end;
        line := s.Strings[index];
      end;

      //set attributes of object
      Attr.Assign(tmpStringList);
      //return last line index of the Stringlist parsed to manage recursion
      result := index;
    finally
      tmpStringList.Free;
    end;
  except
    on e: exception do //format of DFM is incorrect or code contains a bug
      result := -1;
  end;
end;

function TDFMObject.ToString: string;
var
  str: string;
  index: integer;
begin
  if name <> '' then
  begin
    str := 'object ' + name + ': ' + objType;
  end
  else
  begin
    str := 'object ' + objType;
  end;
  for index := 0 to attr.Count - 1 do
    str := str + ansistring(#13#10) + attr.Strings[index];
  for index := 0 to fArrayItemGrpCnt - 1 do
    str := str + ansistring(#13#10) + fArrayItemGrp[index].ToString;
  for index := 0 to fArrayDFMObjCnt - 1 do
    str := str + ansistring(#13#10) + fArrayDFMObj[index].ToString;
  str := str + ansistring(#13#10) + 'end';
  result := str;
end;

function TDFMObject.removeAttribute(name: string): integer;
var
  index: integer;
  linesDeleted: integer;
begin
  linesDeleted := 0;
  result := 0;
  index := retrieveAttrLineNbr(name); //start at the attribute name

  if index = -1 then // did not find attribute
    exit
  else
  begin
    Attr.Delete(index);
    inc(linesDeleted);
  end;

  //delete lines until the line is an attribute
  while (index < (Attr.Count)) and (not isAttribute(attr, index)) do
  begin
    Attr.Delete(index);
    inc(linesDeleted);
  end;

  result := linesDeleted;
end;

procedure TDFMObject.removeItemGrp(name: string);
var
  index: integer;

begin
  index := 0;

  while index < fArrayItemGrpCnt do
  begin
    if fArrayItemGrp[index].name.Equals(name) then
    begin
      FreeAndNil(fArrayItemGrp[index]);
      delete(fArrayItemGrp, index, 1);
      dec(fArrayItemGrpCnt);
    end;
    inc(index);
  end;
end;

function TDFMObject.retrieveAttributeValue(attrName: string): string;
var
  index: integer;
begin
  index := 0;
  result := '';

  while index < (Attr.Count) do
  begin
    if TrimLeft(Attr.Strings[index]).StartsWith(attrName, True) then
    begin
      result := Attr.Strings[index].Substring(Attr.Strings[index].IndexOf('=') + 1,
        Attr.Strings[index].Length - Attr.Strings[index].IndexOf('=') + 1);
      result := TrimLeft(result);
      exit;
    end;
    inc(index);
  end;
end;

function TDFMObject.retrieveObject(componentName: string): TDFMObject;
var
  index: integer;
  tmpObj: TDFMObject;

begin
  result := nil;

  if self.fname.Equals(componentName) then
  begin
    result := self;
  end
  else
  begin
    for index := 0 to ArrayDFMObjCnt - 1 do
    begin
      tmpObj := self.ArrayDFMObject[index].retrieveObject(componentName);
      if tmpObj <> nil then
      begin
        result := tmpObj;
        exit;
      end;
    end;
  end;
end;

//returns -1 when attribute not found
function TDFMObject.retrieveAttrLineNbr(name: string): integer;
var
  index: integer;
begin
  index := 0;
  result := -1;

  while index < (Attr.Count) do
  begin
    if TrimLeft(Attr.Strings[index]).StartsWith(name + ' ', True) then
    begin
      result := index;
      exit;
    end;
    inc(index);
  end;
end;

procedure TDFMObject.setName(n: string);
begin
  fName := n;
end;

procedure TDFMObject.setAttr(a: TStringList);
begin
  Attr := a;
end;

procedure TDFMObject.setFilePath(d: string);
begin
  fFilePath := d;
end;

procedure TDFMObject.setObjType(t: string);
begin
  fObjType := t;
end;

{ TItemGroup }

procedure TDFMItemGrp.insertItem(i: TDFMItem);
begin
  fArrayItems[fArrayItemsCnt] := i;
  inc(fArrayItemsCnt);

  if fArrayItemsCnt = length(fArrayItems) then
    setlength(fArrayItems, length(fArrayItems) * 2);
end;

constructor TDFMItemGrp.Create;
begin
  inherited;
  setlength(fArrayItems, 10);
end;

destructor TDFMItemGrp.Destroy;
var
  i: integer;
begin
  for i := low(fArrayItems) to fArrayItemsCnt - 1 do
    fArrayItems[i].Free;

  inherited;
end;

function TDFMItemGrp.getArrayDFMItem: TArrayDFMItem;
begin
  result := fArrayItems;
end;

function TDFMItemGrp.getArrayItemsCnt: integer;
begin
  result := fArrayItemsCnt;
end;

function TDFMItemGrp.getName: string;
begin
  result := fName;
end;

procedure TDFMItemGrp.setName(n: string);
begin
  fName := n;
end;

function TDFMItemGrp.ToString: string;
var
  str: string;
  index: integer;
begin
  str := fname + ' = <';

  for index := 0 to fArrayItemsCnt - 1 do
    str := str + ansistring(#13#10) + fArrayItems[index].ToString;
  str := str + '>';
  result := str;
end;

function TDFMItemGrp.Parse(s: TStringList; begn: Integer): integer;
var
  index: Integer;
  LastIndex: integer;
  line: string;

begin
  index := begn; //start parsing the ItemGroup header

  line := s.Strings[index];
  //set attribute name
  //Strings[0] is the header format " AttributeName = < ... >"
  self.name := TrimLeft(line).Substring(0, TrimLeft(line).IndexOf('=', 0));
  self.name := trim(self.name);

  //if not empty ItemGroup; if it is empty leave the header so it will be rejected in the While Clause
  if (not TrimRight(line).EndsWith('>')) then
    inc(index);

  line := s.Strings[index];

  while (index <> s.Count) and (not TrimRight(line).EndsWith('>')) do
  begin
    if trimLeft(line).StartsWith('item', True) then
    begin
      Self.insertItem(TDFMItem.Create);
      inc(index); //skip item header
      line := s.Strings[index];
      while (index <> s.Count) and (not TrimLeft(line).StartsWith('end')) do
      begin
        if identifyAttribute(s, index) = 1 then //nested ItemGroup
        begin
          Self.fArrayItems[fArrayItemsCnt - 1].insertItemGrp(TDFMItemGrp.Create);
          LastIndex := Self.fArrayItems[fArrayItemsCnt - 1].fArrayItemGrp[fArrayItems[fArrayItemsCnt - 1].fArrayItemGrpCnt - 1].Parse(s, index);
          index := LastIndex + 1;
        end
        else
        begin
          Self.fArrayItems[fArrayItemsCnt - 1].Attr.Append(line);
          inc(index);
        end;
        line := s.Strings[index];
      end;
    end
    else
    begin
      inc(index);
    end;
    line := s.Strings[index];
  end;

  //return last index parsed to manage recursion
  result := index;
end;

{ TDFMItem }

constructor TDFMItem.Create;
begin
  inherited;
end;

destructor TDFMItem.Destroy;
begin
  inherited;
end;

function TDFMItem.ToString: string;
var
  str: string;
  index: integer;
begin
  if attr.Count = 0 then
    result := ''
  else
  begin
    str := 'item ';
    for index := 0 to attr.Count - 1 do
      str := str + ansistring(#13#10) + attr.Strings[index];
    for index := 0 to fArrayItemGrpCnt - 1 do
      str := str + ansistring(#13#10) + fArrayItemGrp[index].ToString;
    str := str + ansistring(#13#10) + 'end';

    result := str;
  end;
end;

end.

