unit pdfMaker;

{
  Copyright 2019 Stijn Sanders
  https://github.com/stijnsanders/pdfweb
  Made available under the MIT license
}

interface

uses SysUtils, Classes;

//no debug
{$D-}{$Y-}{$L-}

type
  pdfPT=type double;
  pdfID=type cardinal;

  TPdfMaker=class(TObject)
  private
    FOutput:TStream;
    FCompressCode,FFreeOutput:boolean;
    FIDPos:array of int64;
    FIDPosIndex,FIDPosSize:cardinal;
    FPages:array of pdfID;
    FPagesIndex,FPagesSize:cardinal;
    FIDMeta,FIDDoc,FIDPages:pdfID;
    FImgCount:cardinal;
  protected
    function NextID:pdfID;
  public
    constructor Create;
    destructor Destroy; override;
    procedure OpenPdf(const FilePath:string;const Title:AnsiString='';
      const Producer:AnsiString='TPdfMaker');
    procedure OpenPdfStream(const OutputStream:TStream;OwnsStream:boolean;
      const Title:AnsiString='';const Producer:AnsiString='TPdfMaker');
    function ClosePdf:int64;
    function AddObj(const dict:AnsiString):pdfID;
    function AddForm(const res,dict,code:AnsiString):pdfID;
    function AddPage(const res,dict,code:AnsiString):pdfID;
    function AddJPEG(const FilePath:string):AnsiString;
    property PageCount:cardinal read FPagesIndex;
    property CompressCode:boolean read FCompressCode write FCompressCode;
  end;

  EPdfMaker=class(Exception);

function MM_to_pdfPT(x:double):pdfPT;
function Inch_to_pdfPT(x:double):pdfPT;
function pdfPT_to_MM(x:pdfPT):double;
function pdfPT_to_Inch(x:pdfPT):double;

function pdfPT_to_Str(x:pdfPT):AnsiString;
function pdfIDRef(x:pdfID):AnsiString;

function psStr(const x:AnsiString; const suffix:AnsiString=''):AnsiString;
function ps(const x:AnsiString;const v:array of pdfPT):AnsiString;

const
  Helvetica='/Type/Font/Subtype/Type1/BaseFont/Helvetica/Encoding/WinAnsiEncoding';
  HelveticaBold='/Type/Font/Subtype/Type1/BaseFont/Helvetica-Bold/Encoding/WinAnsiEncoding';
  psStr1='Tj'#10;//first line
  psStrN=''''#10;//next lines

implementation

uses Imaging.JPEG, ZLib;

function MM_to_pdfPT(x:double):pdfPT; inline;
begin
  Result:=x*(72.0/25.4);
end;

function Inch_to_pdfPT(x:double):pdfPT; inline;
begin
  Result:=x*72.0;
end;

function pdfPT_to_MM(x:pdfPT):double; inline;
begin
  Result:=x*(25.4/72.0);
end;

function pdfPT_to_Inch(x:pdfPT):double; inline;
begin
  Result:=x/72.0;
end;

function pdfPT_to_Str(x:pdfPT):AnsiString; inline;
begin
  //assert DecimalSeparator='.'
  //Result:=AnsiString(FloatToStr(x));
  Result:=AnsiString(Format('%.2f',[x]));
end;

function pdfIDRef(x:pdfID):AnsiString;
begin
  Result:=AnsiString(Format('%d 0 R',[x]));
end;

function psStr(const x:AnsiString;const suffix:AnsiString):AnsiString;
var
  i,j:cardinal;
  c:AnsiChar;
begin
  SetLength(Result,Length(x)*2+2+Length(suffix));
  Result[1]:='(';
  j:=2;
  for i:=1 to Length(x) do
   begin
    case byte(x[i]) of
      $08:c:='b';
      $09:c:='t';
      $0A:c:='n';
      $0C:c:='f';
      $0D:c:='r';
      $28,$29,$5C:c:=x[i];
      else c:=#0;
    end;
    if c=#0 then
     begin
      Result[j]:=x[i];
      inc(j);
     end
    else
     begin
      Result[j]:='\';
      inc(j);
      Result[j]:=c;
      inc(j);
     end;
   end;
  Result[j]:=')';
  inc(j);
  for i:=1 to Length(suffix) do
   begin
    Result[j]:=suffix[i];
    inc(j);
   end;
  SetLength(Result,j-1);
end;

function ps(const x:AnsiString;const v:array of pdfPT):AnsiString;
var
  i,j,l,vi,vl:cardinal;
begin
  Result:='';
  i:=1;
  l:=Length(x);
  vi:=0;
  vl:=Length(v);
  while i<=l do
   begin
    j:=i;
    while (i<=l) and (x[i]<>'?') do inc(i);
    Result:=Result+Copy(x,j,i-j);
    if (i<=l) then
     begin
      inc(i);//'?'
      if vi<vl then
       begin
        //assert DecimalSeparator='.'
        Result:=Result+pdfPT_to_Str(v[vi]);
        inc(vi);
       end
      else
        raise EPdfMaker.CreateFmt('ps: Insufficient values (%d).',[vi]);
     end;
   end;
  if vi<vl then
    raise EPdfMaker.CreateFmt('ps: Not all values consumed (%d/%d).',[vi,vl]);
end;

function itoa(id:pdfID):AnsiString;
begin
  Result:=AnsiString(IntToStr(id));
end;

{ TPdfMaker }

constructor TPdfMaker.Create;
begin
  inherited Create;
  //defaults
  FOutput:=nil;
  FCompressCode:=true;
  FFreeOutput:=true;
  FIDPosIndex:=0;
  FIDPosSize:=0;
  FPagesIndex:=0;
  FPagesSize:=0;
end;

destructor TPdfMaker.Destroy;
begin
  if FFreeOutput then FreeAndNil(FOutput) else FOutput:=nil;
  inherited;
end;

function TPdfMaker.NextID: pdfID;
begin
  if FOutput=nil then
    raise EPdfMaker.Create('PDfMaker.ClosePdf: No PDF file was opened.');
  if FIDPosIndex=FIDPosSize then
   begin
    inc(FIDPosSize,$400);
    SetLength(FIDPos,FIDPosSize);
   end;
  FIDPos[FIDPosIndex]:=FOutput.Position;
  inc(FIDPosIndex);
  Result:=FIDPosIndex;
end;

procedure TPdfMaker.OpenPdf(const FilePath:string; const Title:AnsiString;
  const Producer:AnsiString);
begin
  OpenPdfStream(TFileStream.Create(FilePath,fmCreate or fmShareDenyWrite),
    true,Title,Producer);
end;

procedure TPdfMaker.OpenPdfStream(const OutputStream:TStream;OwnsStream:boolean;
  const Title,Producer:AnsiString);
var
  ps:AnsiString;
begin
  if FOutput<>nil then
    raise EPdfMaker.Create('PdfMaker.OpenPdf: A PDF file is already opened.');
  if OutputStream.Position<>0 then
    raise EPdfMaker.Create('PdfMaker.OpenPdf: An empty stream is required.');
  FOutput:=OutputStream;
  FFreeOutput:=OwnsStream;
  FIDPosIndex:=0;
  FPagesIndex:=0;
  FImgCount:=0;

  ps:='%PDF-1.7'#10'%'#$ED#$D8#$F8#$CC#10;
  FOutput.Write(ps[1],Length(ps));
  FIDMeta:=NextID;
  ps:=itoa(FIDMeta)+' 0 obj'#10'<<'+
      '/Producer'+psStr(Producer)+
      '/Title'+psStr(Title)+
      '>>'#10'endobj'#10;
  FOutput.Write(ps[1],Length(ps));

  inc(FIDPosIndex);
  FIDDoc:=FIDPosIndex;
  inc(FIDPosIndex);
  FIDPages:=FIDPosIndex;
end;

function TPdfMaker.AddObj(const dict: AnsiString): pdfID;
var
  ps:AnsiString;
begin
  {$IFDEF DEBUG}
  if FOutput=nil then
    raise EPdfMaker.Create('PDfMaker.ClosePdf: No PDF file was opened.');
  {$ENDIF}
  //TODO: validate/parse dict?
  Result:=NextID;
  ps:=itoa(Result)+' 0 obj'#10'<<'+dict+'>>'#10'endobj'#10;
  FOutput.Write(ps[1],Length(ps));
end;

function TPdfMaker.ClosePdf: int64;
var
  ps:AnsiString;
  i:cardinal;
begin
  if FOutput=nil then
    raise EPdfMaker.Create('PDfMaker.ClosePdf: No PDF file was opened.');
  try

    //document info
    ps:=itoa(FIDDoc)+' 0 obj'#10'<</Type/Catalog/Pages '+pdfIDRef(FIDPages)+
      '>>'#10'endobj'#10;
    FIDPos[FIDDoc-1]:=FOutput.Position;
    FOutput.Write(ps[1],Length(ps));

    //page catalog
    ps:=itoa(FIDPages)+' 0 obj'#10'<</Type/Pages/Count '+itoa(FPagesIndex)+
      '/Kids[ ';
    for i:=0 to FPagesIndex-1 do
      ps:=ps+pdfIDRef(FPages[i])+' ';
    ps:=ps+']>>'#10'endobj'#10;
    FIDPos[FIDPages-1]:=FOutput.Position;
    FOutput.Write(ps[1],Length(ps));

    //xref
    ps:='xref'#10'0 '+itoa(FIDPosIndex+1)+#10'0000000000 65535 f '#10;
    for i:=0 to FIDPosIndex-1 do
      ps:=ps+AnsiString(Format('%.10d 00000 n '#10,[FIDPos[i]]));
    ps:=ps+'trailer'#10'<<'+
      '/Size '+itoa(FIDPosIndex+1)+
      '/Info '+pdfIDRef(FIDMeta)+
      '/Root '+pdfIDRef(FIDDoc)+
      '>>'#10'startxref'#10+AnsiString(IntToStr(FOutput.Position))+
      #10'%%EOF'#10;
    FOutput.Write(ps[1],Length(ps));

  finally
    //done, close output
    Result:=FOutput.Position;
    if FFreeOutput then FreeAndNil(FOutput) else FOutput:=nil;
    FIDPosIndex:=0;
    FPagesIndex:=0;
  end;
end;

function TPdfMaker.AddForm(const res, dict, code: AnsiString): pdfID;
var
  ps:AnsiString;
  p:pointer;
  i:integer;
begin
  Result:=NextID;
  //TODO: check dict has /BBox,/Matrix
  ps:=itoa(Result)+' 0 obj'#10'<</Type/XObject/Subtype/Form'#10'/Resources<<'+
    '/ProcSet[/PDF/Text/ImageB/ImageC/ImageI]'+res+
    '>>'#10+dict;
  FOutput.Write(ps[1],Length(ps));
  if FCompressCode and (code<>'') then
   begin
    ZCompress(pointer(@code[1]),Length(code),p,i,zcMax);
    ps:='/Filter/FlateDecode/Length '+itoa(i)+'>>'#10'stream'#10;
    FOutput.Write(ps[1],Length(ps));
    FOutput.Write(p^,i);
    FreeMem(p);
   end
  else
   begin
    Write('/Length '+itoa(Length(code))+'>>'#10'stream'#10);
    FOutput.Write(code[1],Length(code));
   end;
  ps:=#10'endstream'#10'endobj'#10;
  FOutput.Write(ps[1],Length(ps));
end;

function TPdfMaker.AddPage(const res, dict, code: AnsiString): pdfID;
var
  ps:AnsiString;
  p:pointer;
  i:integer;
begin
  Result:=NextID;
  //TODO: check dict has /MediaBox and others?
  if FPagesIndex=FPagesSize then
   begin
    inc(FPagesSize,$100);
    SetLength(FPages,FPagesSize);
   end;
  FPages[FPagesIndex]:=Result;
  inc(FPagesIndex);
  ps:=itoa(Result)+' 0 obj'#10'<</Type/Page/Parent '+pdfIDRef(FIDPages)+
    '/Resources<</ProcSet[/PDF/Text/ImageB/ImageC/ImageI]'+res+
    '>>'+dict+'/Contents '+pdfIDRef(Result+1)+'>>'#10'endobj'#10;
  FOutput.Write(ps[1],Length(ps));
  if FCompressCode and (code<>'') then
   begin
    ZCompress(@code[1],Length(code),p,i,zcMax);
    ps:=itoa(NextID)+' 0 obj'#10'<</Filter/FlateDecode/Length '+itoa(i)+'>>'#10'stream'#10;
    FOutput.Write(ps[1],Length(ps));
    FOutput.Write(p^,i);
    FreeMem(p);
   end
  else
   begin
    ps:=itoa(NextID)+' 0 obj'#10'<</Length '+itoa(Length(code))+'>>'#10'stream'#10;
    FOutput.Write(ps[1],Length(ps));
    FOutput.Write(code[1],Length(code));
   end;
  ps:=#10'endstream'#10'endobj'#10;
  FOutput.Write(ps[1],Length(ps));
end;

function TPdfMaker.AddJPEG(const FilePath: string): AnsiString;
var
  id:pdfID;
  f:TFileStream;
  fs:int64;
  j:TJPEGImage;
  ps:AnsiString;
  x,y:integer;
  gs:boolean;
begin
  f:=TFileStream.Create(FilePath,fmOpenRead or fmShareDenyWrite);
  try
    inc(FImgCount);
    Result:='Im'+itoa(FImgCount);
    id:=NextID;
    //f.Seek(0,soFromEnd);
    j:=TJPEGImage.Create;
    try
      j.LoadFromStream(f);//get from header
      x:=j.Width;
      y:=j.Height;
      gs:=j.GrayScale;
    finally
      j.Free;
    end;
    fs:=f.Seek(0,soFromEnd);
    ps:=itoa(id)+' 0 obj'#10'<</Type/XObject/Subtype/Image/Name/'+Result+
      '/Filter[/DCTDecode]/ColorSpace';
    if gs then ps:=ps+'/DeviceGray' else ps:=ps+'/DeviceRGB';
    ps:=ps+'/BitsPerComponent 8/Width '+itoa(x)+'/Height '+itoa(y)+
      '/Length '+AnsiString(IntToStr(fs))+'>>'#10'stream'#10;
    FOutput.Write(ps[1],Length(ps));
    f.Position:=0;
    FOutput.CopyFrom(f,fs);
    ps:=#10'endstream'#10'endobj'#10;
    FOutput.Write(ps[1],Length(ps));
  finally
    f.Free;
  end;
end;

end.
