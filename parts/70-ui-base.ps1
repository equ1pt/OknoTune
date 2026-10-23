#region UI
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -Namespace WT -Name Native -MemberDefinition @'
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
'@
if (-not $Snapshot) { [void][WT.Native]::ShowWindow([WT.Native]::GetConsoleWindow(), 0) }

$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OknoTune" Width="1180" Height="800" MinWidth="1040" MinHeight="600"
        WindowStartupLocation="CenterScreen" Background="#0F1115" Foreground="#E6E8EB"
        FontFamily="Segoe UI Variable Text, Segoe UI" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
 <Window.Resources>
  <Style x:Key="Toggle" TargetType="CheckBox">
   <Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="CheckBox">
     <Grid Width="44" Height="24" Background="Transparent">
      <Border x:Name="Track" CornerRadius="12" Background="#252B35" BorderBrush="#3A414D" BorderThickness="1"/>
      <Ellipse x:Name="Thumb" Width="14" Height="14" Fill="#AEB4BF" HorizontalAlignment="Left" Margin="5,0,0,0"/>
     </Grid>
     <ControlTemplate.Triggers>
      <Trigger Property="IsChecked" Value="True">
       <Setter TargetName="Track" Property="Background" Value="#4F8CFF"/>
       <Setter TargetName="Track" Property="BorderBrush" Value="#4F8CFF"/>
       <Setter TargetName="Thumb" Property="Fill" Value="White"/>
       <Setter TargetName="Thumb" Property="HorizontalAlignment" Value="Right"/>
       <Setter TargetName="Thumb" Property="Margin" Value="0,0,5,0"/>
      </Trigger>
      <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.35"/></Trigger>
     </ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="Btn" TargetType="Button">
   <Setter Property="Foreground" Value="#E6E8EB"/><Setter Property="Background" Value="#1C2129"/><Setter Property="BorderBrush" Value="#2E3540"/>
   <Setter Property="Padding" Value="14,8"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FontSize" Value="13"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="Button">
     <Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
      <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
     </Border>
     <ControlTemplate.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#4F8CFF"/></Trigger>
      <Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.4"/></Trigger>
     </ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
   <Setter Property="Background" Value="#4F8CFF"/><Setter Property="BorderBrush" Value="#4F8CFF"/>
   <Setter Property="Foreground" Value="White"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Padding" Value="20,8"/>
  </Style>
  <Style x:Key="Warn" TargetType="Button" BasedOn="{StaticResource Btn}">
   <Setter Property="Background" Value="#2E2610"/><Setter Property="BorderBrush" Value="#6B5418"/><Setter Property="Foreground" Value="#F2CC60"/>
  </Style>
  <Style x:Key="Link" TargetType="Button">
   <Setter Property="Foreground" Value="#7FA8FF"/><Setter Property="FontSize" Value="12"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="Button"><Border Background="Transparent" Padding="2"><ContentPresenter/></Border></ControlTemplate>
   </Setter.Value></Setter>
  </Style>
  <Style x:Key="Chip" TargetType="ToggleButton">
   <Setter Property="Foreground" Value="#AEB4BF"/><Setter Property="FontSize" Value="12"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="ToggleButton">
     <Border x:Name="B" CornerRadius="14" Padding="12,5" Background="#161A20" BorderBrush="#2A303A" BorderThickness="1"><ContentPresenter/></Border>
     <ControlTemplate.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#3D4553"/></Trigger>
      <Trigger Property="IsChecked" Value="True">
       <Setter TargetName="B" Property="Background" Value="#1E2A44"/><Setter TargetName="B" Property="BorderBrush" Value="#4F8CFF"/><Setter Property="Foreground" Value="#CFE0FF"/>
      </Trigger>
     </ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="Seg" TargetType="RadioButton">
   <Setter Property="Foreground" Value="#AEB4BF"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="RadioButton">
     <Border x:Name="B" CornerRadius="7" Padding="18,6" Background="Transparent"><ContentPresenter/></Border>
     <ControlTemplate.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#1F2530"/></Trigger>
      <Trigger Property="IsChecked" Value="True"><Setter TargetName="B" Property="Background" Value="#4F8CFF"/><Setter Property="Foreground" Value="White"/></Trigger>
     </ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="Nav" TargetType="ListBoxItem">
   <Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="ListBoxItem">
     <Border x:Name="B" CornerRadius="8" Padding="12,6" Margin="0,1" Background="Transparent">
      <ContentPresenter/>
     </Border>
     <ControlTemplate.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#1A1F27"/></Trigger>
      <Trigger Property="IsSelected" Value="True"><Setter TargetName="B" Property="Background" Value="#222A36"/></Trigger>
     </ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="ScrollBar">
   <Setter Property="Width" Value="8"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="ScrollBar">
     <Track x:Name="PART_Track" IsDirectionReversed="True">
      <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border CornerRadius="4" Background="#2E3540"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
     </Track>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="Search" TargetType="TextBox">
   <Setter Property="Foreground" Value="#E6E8EB"/><Setter Property="CaretBrush" Value="#E6E8EB"/><Setter Property="FontSize" Value="13"/>
   <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="TextBox">
     <Border x:Name="B" Background="#161A20" BorderBrush="#2A303A" BorderThickness="1" CornerRadius="8" Padding="32,7,10,7">
      <ScrollViewer x:Name="PART_ContentHost"/>
     </Border>
     <ControlTemplate.Triggers><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#4F8CFF"/></Trigger></ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
 </Window.Resources>

 <Grid Background="#0F1115">
  <Grid.ColumnDefinitions><ColumnDefinition Width="250"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

  <!-- Sidebar -->
  <Border Background="#13161C" BorderBrush="#1E232B" BorderThickness="0,0,1,0">
   <DockPanel Margin="16,24,16,18">
    <StackPanel DockPanel.Dock="Top" Margin="8,0,0,16">
     <StackPanel Orientation="Horizontal">
      <Border Width="32" Height="32" CornerRadius="9" Background="#4F8CFF">
       <TextBlock Text="&#xE945;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="White" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <TextBlock Text="OknoTune" FontSize="21" FontWeight="SemiBold" Margin="12,0,0,0" VerticalAlignment="Center"/>
     </StackPanel>
     <TextBlock Text="Настройка Windows с откатом" Foreground="#8B93A1" FontSize="12" Margin="0,10,0,0"/>
    </StackPanel>
    <StackPanel DockPanel.Dock="Bottom" Margin="8,10,0,0">
     <TextBlock x:Name="SysInfo" Foreground="#5F6774" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,10"/>
     <Button x:Name="BtnReport" Content="Сообщить о проблеме" Style="{StaticResource Btn}" HorizontalAlignment="Left" FontSize="12" Padding="12,6" Margin="0,0,0,6" ToolTip="Открыть форму обратной связи: версия программы, Windows и журнал заполнятся сами"/>
     <Button x:Name="BtnLog" Content="Папка журнала" Style="{StaticResource Btn}" HorizontalAlignment="Left" FontSize="12" Padding="12,6"/>
    </StackPanel>
    <ListBox x:Name="Nav" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Nav}" ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.VerticalScrollBarVisibility="Auto"/>
   </DockPanel>
  </Border>

  <Grid Grid.Column="1">
   <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

   <!-- Home -->
   <ScrollViewer x:Name="HomeView" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
    <StackPanel Margin="40,34,40,28" MaxWidth="980" HorizontalAlignment="Left">
     <TextBlock Text="Настроим Windows" FontSize="28" FontWeight="SemiBold"/>
     <TextBlock Text="Ответьте на несколько вопросов «да/нет», проверьте, что изменится, и примените. Любое изменение можно откатить." Foreground="#8B93A1" FontSize="14" Margin="0,6,0,0" TextWrapping="Wrap"/>
     <Border Background="#171B22" BorderBrush="#232831" BorderThickness="1" CornerRadius="14" Padding="24,20" Margin="0,22,0,0">
      <Grid>
       <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
       <StackPanel>
        <StackPanel Orientation="Horizontal">
         <TextBlock x:Name="HomeCount" FontSize="32" FontWeight="SemiBold"/>
         <TextBlock Text="настроек уже применено" Foreground="#8B93A1" FontSize="14" Margin="12,0,0,6" VerticalAlignment="Bottom"/>
        </StackPanel>
        <ProgressBar x:Name="HomeBar" Height="6" Margin="0,12,24,0" Foreground="#4ADE80" Background="#232A35" BorderThickness="0"/>
       </StackPanel>
       <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="12,0,0,0">
        <TextBlock x:Name="HomeApps" Foreground="#AEB4BF" FontSize="13"/>
        <TextBlock x:Name="HomeSnaps" Foreground="#AEB4BF" FontSize="13" Margin="0,6,0,0"/>
       </StackPanel>
      </Grid>
     </Border>
     <Border x:Name="RebootBanner" Visibility="Collapsed" Background="#2A2311" BorderBrush="#6B5418" BorderThickness="1" CornerRadius="12" Padding="20,14" Margin="0,12,0,0">
      <Grid>
       <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
       <TextBlock Text="Часть изменений заработает только после перезагрузки." Foreground="#F2CC60" FontSize="13" VerticalAlignment="Center"/>
       <Button x:Name="BtnReboot2" Grid.Column="1" Content="Перезагрузить" Style="{StaticResource Warn}"/>
      </Grid>
     </Border>
     <Border Background="#16213A" BorderBrush="#2B4A86" BorderThickness="1" CornerRadius="16" Padding="28,24" Margin="0,16,0,0">
      <Grid>
       <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
       <Border Width="52" Height="52" CornerRadius="14" Background="#4F8CFF" VerticalAlignment="Top">
        <TextBlock Text="&#xE945;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="White" FontSize="24" HorizontalAlignment="Center" VerticalAlignment="Center"/>
       </Border>
       <StackPanel Grid.Column="1" Margin="20,0,0,0">
        <TextBlock Text="Быстрая настройка" FontSize="20" FontWeight="SemiBold"/>
        <TextBlock Text="Несколько вопросов «да/нет» о том, как вы пользуетесь компьютером. Железо определим сами. OknoTune подберёт настройки и перед применением покажет, что изменится." Foreground="#AEB8CC" FontSize="13" TextWrapping="Wrap" Margin="0,6,0,0"/>
        <TextBlock x:Name="HomePlan" Foreground="#9DB4FF" FontSize="13" Margin="0,12,0,0"/>
        <StackPanel Orientation="Horizontal" Margin="0,16,0,0">
         <Button x:Name="BtnStart" Content="Начать" Style="{StaticResource Primary}" Padding="28,10" FontSize="14"/>
         <Button x:Name="BtnManual" Content="Все настройки вручную" Style="{StaticResource Btn}" Margin="10,0,0,0" Padding="18,10"/>
        </StackPanel>
       </StackPanel>
      </Grid>
     </Border>
     <TextBlock Text="Что значат цвета" FontSize="15" FontWeight="SemiBold" Margin="0,24,0,10"/>
     <UniformGrid Columns="2">
      <StackPanel Orientation="Horizontal" Margin="0,0,0,10"><Border Width="4" Height="34" CornerRadius="2" Background="#3FB950"/><StackPanel Margin="12,0,0,0"><TextBlock Text="Ничего не теряете" FontWeight="SemiBold" FontSize="13"/><TextBlock Text="Включается автоматически" Foreground="#8B93A1" FontSize="12"/></StackPanel></StackPanel>
      <StackPanel Orientation="Horizontal" Margin="0,0,0,10"><Border Width="4" Height="34" CornerRadius="2" Background="#D29922"/><StackPanel Margin="12,0,0,0"><TextBlock Text="Мелкие ограничения" FontWeight="SemiBold" FontSize="13"/><TextBlock Text="Что-то станет чуть иначе, написано на карточке" Foreground="#8B93A1" FontSize="12"/></StackPanel></StackPanel>
      <StackPanel Orientation="Horizontal" Margin="0,0,0,10"><Border Width="4" Height="34" CornerRadius="2" Background="#F85149"/><StackPanel Margin="12,0,0,0"><TextBlock Text="Отключается функция" FontWeight="SemiBold" FontSize="13"/><TextBlock Text="Перестанет работать то, что указано" Foreground="#8B93A1" FontSize="12"/></StackPanel></StackPanel>
      <StackPanel Orientation="Horizontal" Margin="0,0,0,10"><Border Width="4" Height="34" CornerRadius="2" Background="#A371F7"/><StackPanel Margin="12,0,0,0"><TextBlock Text="Удаление приложения" FontWeight="SemiBold" FontSize="13"/><TextBlock Text="Вернуть можно из Microsoft Store" Foreground="#8B93A1" FontSize="12"/></StackPanel></StackPanel>
     </UniformGrid>
    </StackPanel>
   </ScrollViewer>

   <!-- Wizard -->
   <Grid x:Name="WizardView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Margin="40,30,40,10">
     <TextBlock Text="Быстрая настройка" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock Text="Ответы уже подставлены: железо определено автоматически, остальное по тому, что сейчас настроено на этом ПК. Поменяйте то, что не так. Зелёные настройки (без потерь) включатся в любом случае." Foreground="#8B93A1" FontSize="13" Margin="0,6,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="40,0,32,12">
     <StackPanel x:Name="WizList" MaxWidth="900" HorizontalAlignment="Left"/>
    </ScrollViewer>
    <Border Grid.Row="2" Background="#13161C" BorderBrush="#1E232B" BorderThickness="0,1,0,0" Padding="40,14">
     <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="WizCount" FontSize="13" Foreground="#AEB4BF" VerticalAlignment="Center"/>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
       <Button x:Name="WizBack" Content="Назад" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
       <Button x:Name="WizNext" Content="Дальше: что изменится" Style="{StaticResource Primary}"/>
      </StackPanel>
     </Grid>
    </Border>
   </Grid>

   <!-- List -->
   <Grid x:Name="ListView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <StackPanel Margin="32,26,32,12">
     <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel>
       <TextBlock x:Name="Heading" Text="Все настройки" FontSize="26" FontWeight="SemiBold"/>
       <TextBlock x:Name="SubHeading" Foreground="#8B93A1" FontSize="13" Margin="0,4,0,0"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
       <Button x:Name="BtnSafe" Content="Отметить зелёные" Style="{StaticResource Btn}" Margin="0,0,10,0"/>
       <Grid Width="220">
        <TextBox x:Name="Search" Style="{StaticResource Search}"/>
        <TextBlock Text="&#xE721;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="#6B7380" FontSize="13" Margin="12,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
        <TextBlock x:Name="SearchHint" Text="Поиск" Foreground="#6B7380" FontSize="13" Margin="33,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
       </Grid>
      </StackPanel>
     </Grid>
     <Grid Margin="0,14,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel Orientation="Horizontal">
       <ToggleButton x:Name="ChipPending" Content="Не применено" Style="{StaticResource Chip}" Margin="0,0,8,0"/>
       <ToggleButton x:Name="ChipSafe" Content="Без потерь" Style="{StaticResource Chip}" Margin="0,0,8,0"/>
       <ToggleButton x:Name="ChipReboot" Content="С перезагрузкой" Style="{StaticResource Chip}"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
       <Ellipse Width="8" Height="8" Fill="#3FB950"/><TextBlock Text="без потерь" Foreground="#8B93A1" FontSize="12" Margin="6,0,12,0"/>
       <Ellipse Width="8" Height="8" Fill="#D29922"/><TextBlock Text="мелочи" Foreground="#8B93A1" FontSize="12" Margin="6,0,12,0"/>
       <Ellipse Width="8" Height="8" Fill="#F85149"/><TextBlock Text="отключает функцию" Foreground="#8B93A1" FontSize="12" Margin="6,0,12,0"/>
       <Ellipse Width="8" Height="8" Fill="#A371F7"/><TextBlock Text="удаление" Foreground="#8B93A1" FontSize="12" Margin="6,0,0,0"/>
      </StackPanel>
     </Grid>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="32,0,24,12">
     <StackPanel x:Name="List"/>
    </ScrollViewer>
   </Grid>

   <!-- History -->
   <Grid x:Name="HistoryView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <StackPanel Margin="40,30,40,16">
     <TextBlock Text="История изменений" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock x:Name="HistSub" Foreground="#8B93A1" FontSize="13" Margin="0,6,0,0" TextWrapping="Wrap"/>
     <Button x:Name="BtnHistClear" Content="Очистить историю" Style="{StaticResource Btn}" FontSize="12" Padding="12,6" Margin="0,14,0,0" HorizontalAlignment="Left"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="40,0,32,16">
     <StackPanel x:Name="HistList" MaxWidth="900" HorizontalAlignment="Left"/>
    </ScrollViewer>
   </Grid>

   <!-- Cleanup -->
   <Grid x:Name="CleanView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Margin="40,30,40,14">
     <TextBlock Text="Очистка диска" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock Text="Удаляет временные и ненужные файлы. Документы, фото, загрузки и настройки программ не трогаются." Foreground="#8B93A1" FontSize="13" Margin="0,6,0,0" TextWrapping="Wrap"/>
     <Border Background="#171B22" BorderBrush="#232831" BorderThickness="1" CornerRadius="14" Padding="24,16" Margin="0,16,0,0" MaxWidth="900" HorizontalAlignment="Stretch">
      <Grid>
       <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
       <StackPanel>
        <TextBlock x:Name="CleanTotal" FontSize="28" FontWeight="SemiBold"/>
        <TextBlock Text="можно освободить с выбранными пунктами" Foreground="#8B93A1" FontSize="13"/>
       </StackPanel>
       <TextBlock x:Name="CleanDisk" Grid.Column="1" Foreground="#AEB4BF" FontSize="13" VerticalAlignment="Center"/>
      </Grid>
     </Border>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="40,0,32,12">
     <StackPanel x:Name="CleanList" MaxWidth="900" HorizontalAlignment="Stretch"/>
    </ScrollViewer>
    <Border Grid.Row="2" Background="#13161C" BorderBrush="#1E232B" BorderThickness="0,1,0,0" Padding="40,14">
     <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
       <TextBlock x:Name="CleanStatus" FontSize="13" Foreground="#AEB4BF" TextTrimming="CharacterEllipsis"/>
       <ProgressBar x:Name="CleanBar" Height="3" Margin="0,6,0,0" Visibility="Collapsed" Foreground="#4F8CFF" Background="#232A35" BorderThickness="0" Maximum="100"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
       <Button x:Name="BtnCleanMgr" Content="Очистка диска Windows" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
       <Button x:Name="BtnRescan" Content="Пересчитать" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
       <Button x:Name="BtnClean" Content="Очистить" Style="{StaticResource Primary}"/>
      </StackPanel>
     </Grid>
    </Border>
   </Grid>

   <!-- Drivers -->
   <Grid x:Name="DriversView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Margin="40,30,40,14">
     <TextBlock Text="Драйверы" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock Text="OknoTune ничего не скачивает сам: он определяет железо, показывает возраст драйверов и открывает страницу в браузере. Надёжнее всего — сайт производителя. driver.ru и поиск Google — неофициальные источники: скачивайте оттуда только если на сайте производителя драйвера нет, и проверяйте файл антивирусом." Foreground="#8B93A1" FontSize="13" Margin="0,6,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="40,0,32,12">
     <StackPanel x:Name="DrvList" MaxWidth="900" HorizontalAlignment="Stretch"/>
    </ScrollViewer>
    <Border Grid.Row="2" Background="#13161C" BorderBrush="#1E232B" BorderThickness="0,1,0,0" Padding="40,14">
     <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="DrvStatus" FontSize="13" Foreground="#AEB4BF" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
       <Button x:Name="BtnWuDrivers" Content="Драйверы в Windows Update" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
       <Button x:Name="BtnDevMgr" Content="Диспетчер устройств" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
       <Button x:Name="BtnDrvRescan" Content="Проверить заново" Style="{StaticResource Btn}"/>
      </StackPanel>
     </Grid>
    </Border>
   </Grid>

   <!-- Apps -->
   <Grid x:Name="AppsView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <StackPanel Margin="40,30,40,4">
     <TextBlock Text="Полезные программы" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock Text="Проверенные бесплатные программы. «Установить» скачивает обычный установщик с сайта разработчика через winget (не версию из Microsoft Store) и запускает его в отдельном окне. «Сайт» открывает страницу программы." Foreground="#8B93A1" FontSize="13" Margin="0,6,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="40,0,32,16">
     <StackPanel x:Name="AppsList" MaxWidth="900" HorizontalAlignment="Stretch"/>
    </ScrollViewer>
   </Grid>

   <!-- Fixes -->
   <Grid x:Name="FixView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <StackPanel Margin="40,30,40,4">
     <TextBlock Text="Исправления" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock Text="Что-то перестало работать после настройки? Исправление включит нужные службы Windows и сбросит то, что обычно ломается. Отключённое OknoTune или другой программой — неважно." Foreground="#8B93A1" FontSize="13" Margin="0,6,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="40,0,32,16">
     <StackPanel x:Name="FixList" MaxWidth="900" HorizontalAlignment="Stretch"/>
    </ScrollViewer>
   </Grid>

   <!-- Startup -->
   <Grid x:Name="StartupView" Visibility="Collapsed">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Margin="40,30,40,14">
     <TextBlock Text="Автозагрузка" FontSize="26" FontWeight="SemiBold"/>
     <TextBlock Text="Программы, которые Windows запускает при входе в систему. Отключение обратимо: OknoTune хранит отключённую запись и возвращает её одним нажатием." Foreground="#8B93A1" FontSize="13" Margin="0,6,0,0" TextWrapping="Wrap"/>
     <Border Background="#171B22" BorderBrush="#232831" BorderThickness="1" CornerRadius="14" Padding="24,14" Margin="0,16,0,0" MaxWidth="900" HorizontalAlignment="Stretch">
      <TextBlock x:Name="SuSummary" FontSize="13" Foreground="#AEB4BF" TextWrapping="Wrap"/>
     </Border>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="40,0,32,12">
     <StackPanel x:Name="SuList" MaxWidth="900" HorizontalAlignment="Stretch"/>
    </ScrollViewer>
    <Border Grid.Row="2" Background="#13161C" BorderBrush="#1E232B" BorderThickness="0,1,0,0" Padding="40,14">
     <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="SuStatus" FontSize="13" Foreground="#AEB4BF" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
       <Button x:Name="BtnSuRescan" Content="Проверить заново" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
       <Button x:Name="BtnSuApply" Content="Применить" Style="{StaticResource Primary}" IsEnabled="False"/>
      </StackPanel>
     </Grid>
    </Border>
   </Grid>

   <TextBlock x:Name="Loading" Text="Проверяю систему…" Foreground="#8B93A1" FontSize="14" HorizontalAlignment="Center" VerticalAlignment="Center"/>
   <StackPanel x:Name="Busy" Width="340" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed" IsHitTestVisible="False">
    <TextBlock x:Name="BusyText" Foreground="#8B93A1" FontSize="14" HorizontalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center"/>
    <ProgressBar x:Name="BusyBar" Height="4" Margin="0,12,0,0" Foreground="#4F8CFF" Background="#232A35" BorderThickness="0" Maximum="100"/>
   </StackPanel>

   <!-- Footer (list view) -->
   <Border x:Name="Footer" Grid.Row="1" Visibility="Collapsed" Background="#13161C" BorderBrush="#1E232B" BorderThickness="0,1,0,0" Padding="32,14">
    <Grid>
     <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
     <TextBlock x:Name="Status" FontSize="13" Foreground="#AEB4BF" TextTrimming="CharacterEllipsis" VerticalAlignment="Center" Margin="0,0,16,0"/>
     <StackPanel Grid.Column="1" Orientation="Horizontal">
      <Button x:Name="BtnReboot" Content="Перезагрузить" Style="{StaticResource Warn}" Margin="0,0,8,0" Visibility="Collapsed"/>
      <Button x:Name="BtnProfSave" Content="Сохранить профиль" Style="{StaticResource Btn}" Margin="0,0,8,0" ToolTip="Сохранить выбранные настройки в файл, чтобы применить их на другом ПК"/>
      <Button x:Name="BtnProfLoad" Content="Загрузить профиль" Style="{StaticResource Btn}" Margin="0,0,8,0" ToolTip="Отметить настройки из файла профиля. Применяются они только после проверки"/>
      <Button x:Name="BtnReset" Content="Сбросить выбор" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
      <Button x:Name="BtnApply" Content="Проверить и применить" Style="{StaticResource Primary}" IsEnabled="False"/>
     </StackPanel>
    </Grid>
   </Border>
  </Grid>

  <!-- Overlay dialog -->
  <Grid x:Name="Overlay" Grid.ColumnSpan="2" Background="#B3080A0E" Visibility="Collapsed">
   <Border Width="660" MaxHeight="680" Background="#151920" BorderBrush="#2A303A" BorderThickness="1" CornerRadius="14" VerticalAlignment="Center" HorizontalAlignment="Center">
    <Grid Margin="28,24">
     <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
     <StackPanel>
      <TextBlock x:Name="OvTitle" FontSize="22" FontWeight="SemiBold"/>
      <TextBlock x:Name="OvSub" Foreground="#8B93A1" FontSize="13" Margin="0,4,0,0" TextWrapping="Wrap"/>
     </StackPanel>
     <ScrollViewer Grid.Row="1" Margin="0,16,0,0" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="OvBody" Margin="0,0,10,0"/></ScrollViewer>
     <ProgressBar x:Name="OvProgress" Grid.Row="2" Height="4" Margin="0,14,0,0" Visibility="Collapsed" Foreground="#4F8CFF" Background="#232A35" BorderThickness="0" Maximum="100"/>
     <Grid Grid.Row="3" Margin="0,20,0,0">
      <StackPanel x:Name="OvLeft" Orientation="Horizontal" VerticalAlignment="Center"/>
      <StackPanel x:Name="OvButtons" Orientation="Horizontal" HorizontalAlignment="Right"/>
     </Grid>
    </Grid>
   </Border>
  </Grid>
 </Grid>
</Window>
'@

$CardXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" CornerRadius="10" Margin="0,0,0,10" Background="#171B22" BorderBrush="#232831" BorderThickness="1">
 <Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="5"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <Border Name="Stripe" CornerRadius="9,0,0,9"/>
  <StackPanel Grid.Column="1" Margin="16,13,0,13">
   <WrapPanel>
    <TextBlock Name="T" FontSize="15" FontWeight="SemiBold" Foreground="#E6E8EB" Margin="0,0,10,0" VerticalAlignment="Center"/>
    <Border Name="Boot" CornerRadius="9" Padding="8,1" Background="#1F2638" VerticalAlignment="Center" Visibility="Collapsed"><TextBlock Text="перезагрузка" FontSize="11" Foreground="#9DB4FF"/></Border>
   </WrapPanel>
   <TextBlock Name="Sh" TextWrapping="Wrap" Foreground="#AEB4BF" FontSize="13" Margin="0,4,0,0"/>
   <TextBlock Name="W" TextWrapping="Wrap" FontSize="13" Margin="0,4,0,0" Visibility="Collapsed"/>
   <TextBlock Name="D" TextWrapping="Wrap" Foreground="#8B93A1" FontSize="13" Margin="0,8,0,0" Visibility="Collapsed"/>
   <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
    <TextBlock Name="S" FontSize="12" VerticalAlignment="Center"/>
    <Button Name="More" Content="Подробнее ▾" Margin="14,0,0,0" VerticalAlignment="Center"/>
   </StackPanel>
  </StackPanel>
  <CheckBox Name="C" Grid.Column="2" VerticalAlignment="Center" Margin="20,0,18,0"/>
 </Grid>
</Border>
'@
$HeaderXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Margin="2,18,4,10">
 <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
 <TextBlock Name="L" FontSize="11" FontWeight="SemiBold" Foreground="#6B7380" VerticalAlignment="Center"/>
 <Button Name="All" Grid.Column="1" Content="Отметить всё в разделе"/>
</Grid>
'@
$NavXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
 <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
 <TextBlock Name="G" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="15" Foreground="#AEB4BF" VerticalAlignment="Center"/>
 <TextBlock Name="L" Grid.Column="1" FontSize="14" Foreground="#E6E8EB" Margin="12,0,0,0" VerticalAlignment="Center"/>
 <Border Name="Badge" Grid.Column="2" CornerRadius="9" Background="#4F8CFF" Padding="7,1" Visibility="Collapsed" VerticalAlignment="Center">
  <TextBlock Name="BadgeT" FontSize="11" Foreground="White" FontWeight="SemiBold"/>
 </Border>
</Grid>
'@
$QuestionXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" CornerRadius="10" Padding="20,14" Margin="0,0,0,8" Background="#171B22" BorderBrush="#232831" BorderThickness="1">
 <Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <StackPanel>
   <TextBlock Name="Q" FontSize="15" FontWeight="SemiBold" Foreground="#E6E8EB" TextWrapping="Wrap"/>
   <TextBlock Name="H" FontSize="13" Foreground="#8B93A1" TextWrapping="Wrap" Margin="0,4,0,0"/>
   <TextBlock Name="A" Text="определено автоматически" FontSize="11" Foreground="#7FA8FF" Margin="0,6,0,0" Visibility="Collapsed"/>
  </StackPanel>
  <Border Grid.Column="1" CornerRadius="9" Background="#12151B" BorderBrush="#2A303A" BorderThickness="1" Padding="3" VerticalAlignment="Center" Margin="24,0,0,0">
   <StackPanel Orientation="Horizontal">
    <RadioButton Name="Y" Content="Да"/>
    <RadioButton Name="N" Content="Нет"/>
   </StackPanel>
  </Border>
 </Grid>
</Border>
'@
$HistXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" CornerRadius="10" Padding="20,15" Margin="0,0,0,10" Background="#171B22" BorderBrush="#232831" BorderThickness="1">
 <Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <StackPanel>
   <TextBlock Name="T" FontSize="15" FontWeight="SemiBold" Foreground="#E6E8EB"/>
   <TextBlock Name="S" FontSize="12" Foreground="#8B93A1" Margin="0,4,0,0"/>
   <TextBlock Name="L" FontSize="13" Foreground="#AEB4BF" TextWrapping="Wrap" Margin="0,8,0,0"/>
  </StackPanel>
  <Button Name="B" Grid.Column="1" Content="Откатить" VerticalAlignment="Center" Margin="24,0,0,0"/>
 </Grid>
</Border>
'@

$script:Win = [Windows.Markup.XamlReader]::Parse($Xaml)
foreach ($n in 'Nav', 'SysInfo', 'BtnLog', 'HomeView', 'HomeCount', 'HomeBar', 'HomeApps', 'HomeSnaps', 'HomePlan', 'RebootBanner', 'BtnReboot2', 'BtnStart', 'BtnManual',
               'WizardView', 'WizList', 'WizCount', 'WizBack', 'WizNext', 'ListView', 'Heading', 'SubHeading', 'BtnSafe', 'Search', 'SearchHint',
               'ChipPending', 'ChipSafe', 'ChipReboot', 'List', 'HistoryView', 'HistSub', 'HistList', 'BtnHistClear', 'Loading', 'Footer', 'Status', 'BtnReboot', 'BtnReset', 'BtnApply',
               'Overlay', 'OvTitle', 'OvSub', 'OvBody', 'OvProgress', 'OvLeft', 'OvButtons',
               'CleanView', 'CleanTotal', 'CleanDisk', 'CleanList', 'CleanStatus', 'BtnCleanMgr', 'BtnRescan', 'BtnClean',
               'StartupView', 'SuSummary', 'SuList', 'SuStatus', 'BtnSuRescan', 'BtnSuApply',
               'DriversView', 'DrvList', 'DrvStatus', 'BtnWuDrivers', 'BtnDevMgr', 'BtnDrvRescan', 'AppsView', 'AppsList', 'FixView', 'FixList', 'BtnProfSave', 'BtnProfLoad', 'Busy', 'BusyText', 'BusyBar', 'CleanBar', 'BtnReport') {
    Set-Variable -Scope Script -Name $n -Value $script:Win.FindName($n)
}
$script:Styles = @{}
foreach ($s in 'Toggle', 'Btn', 'Primary', 'Warn', 'Link', 'Seg') { $script:Styles[$s] = $script:Win.FindResource($s) }
$bc = New-Object Windows.Media.BrushConverter
function Brush([string]$hex) { $bc.ConvertFromString($hex) }
function New-Xaml([string]$x) { [Windows.Markup.XamlReader]::Parse($x) }

$Cats = [ordered]@{ 'Приватность' = 0xE72E; 'Реклама' = 0xE789; 'Игры' = 0xE7FC; 'Система' = 0xE713; 'Обновления' = 0xE777; 'Службы' = 0xE90F
                    'Безопасность' = 0xEA18; 'Удобство' = 0xE771; 'Компоненты' = 0xE7B8; 'Приложения' = 0xE719 }
$ImpactColor = @{ none = '#3FB950'; minor = '#D29922'; breaks = '#F85149'; remove = '#A371F7' }
$ImpactText = @{ none = 'Ничего не теряете'; minor = 'Мелкие ограничения'; breaks = 'Отключается функция Windows'; remove = 'Удаление приложения' }
$WarnColor = @{ minor = '#E3B341'; breaks = '#FF7B72'; remove = '#C4A5FF' }
$script:CurCat = 'Все'; $script:CurView = 'home'; $script:Answers = @{}; $script:NavBusy = $false
$script:Headers = @{}; $script:NavItems = @{}; $script:QRadios = @{}
$script:Ru = [Globalization.CultureInfo]'ru-RU'

function Pump { $script:Win.Dispatcher.Invoke([Action] {}, [Windows.Threading.DispatcherPriority]::Background) }

#region Background work (окно не зависает, пока идёт скан)
# $work выполняется в отдельном runspace: туда копируются функции $fns и переменные $vars.
# $work получает $sync: Value (0..100), Text, Partial (промежуточные результаты); его вывод попадает в $sync.Result.
# $tick вызывается в потоке UI каждые 150 мс, $done — один раз в конце (ошибка — в $sync.Error).
$script:BgJobs = @{}
function Start-Bg([string]$key, [string[]]$fns, [hashtable]$vars, [scriptblock]$work, [scriptblock]$tick, [scriptblock]$done) {
    if ($script:BgJobs[$key]) { return }   # уже идёт
    $iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($f in $fns) { $iss.Commands.Add((New-Object Management.Automation.Runspaces.SessionStateFunctionEntry $f, (Get-Item "function:$f").Definition)) }
    foreach ($k in $vars.Keys) { $iss.Variables.Add((New-Object Management.Automation.Runspaces.SessionStateVariableEntry $k, $vars[$k], '')) }
    $sync = [hashtable]::Synchronized(@{ Done = $false; Error = $null; Result = $null; Value = 0; Text = ''; Partial = [hashtable]::Synchronized(@{}) })
    $ps = [powershell]::Create($iss)
    # скрипт-блоки нельзя выполнять в чужом runspace — передаём текст и собираем заново
    [void]$ps.AddScript({
        param($code, $sync)
        try { $sync.Result = @(& ([scriptblock]::Create($code)) $sync) } catch { $sync.Error = "$_" } finally { $sync.Done = $true }
    }).AddArgument($work.ToString()).AddArgument($sync)
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150); $timer.Tag = $key
    $timer.Add_Tick({ Step-Bg $this.Tag })
    $script:BgJobs[$key] = @{ Ps = $ps; Sync = $sync; Tick = $tick; Done = $done; Timer = $timer; Async = $ps.BeginInvoke() }
    $timer.Start()
}
function Step-Bg([string]$key) {
    $j = $script:BgJobs[$key]
    if (-not $j) { return }
    if ($j.Tick) { & $j.Tick $j.Sync }
    if (-not $j.Sync.Done) { return }
    $j.Timer.Stop(); $script:BgJobs.Remove($key)
    try { $j.Ps.Runspace.Close(); $j.Ps.Dispose() } catch {}
    & $j.Done $j.Sync
}
function Wait-Bg {
    # для -Snapshot: дождаться всех фоновых задач, не полагаясь на таймер
    while ($script:BgJobs.Count) { foreach ($k in @($script:BgJobs.Keys)) { Step-Bg $k }; Start-Sleep -Milliseconds 50 }
}
# Надпись с полосой по центру вкладки, пока идёт её скан; видна только на своей вкладке.
$script:BusyState = @{}
function Set-Busy([string]$view, [string]$text, [double]$value) { $script:BusyState[$view] = @{ Text = $text; Value = $value }; Update-Busy }
function Clear-Busy([string]$view) { $script:BusyState.Remove($view); Update-Busy }
function Update-Busy {
    $b = $script:BusyState[$script:CurView]
    $script:Busy.Visibility = $(if ($b) { 'Visible' } else { 'Collapsed' })
    if ($b) { $script:BusyText.Text = $b.Text; $script:BusyBar.Value = $b.Value }
}
#endregion
function Write-Log([string]$m) {
    Add-Content -Path $script:LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $m) -Encoding UTF8
    $script:Status.Text = $m
    if ($script:Overlay.Visibility -eq 'Visible' -and $script:OvProgress.Visibility -eq 'Visible') { $script:OvSub.Text = $m }
}
function Test-Pending($it) { $it.Toggle -and $it.Toggle.IsEnabled -and ([bool]$it.Toggle.IsChecked -ne ($it.State -eq 'on')) }
function Get-Verb($it, [switch]$Done) {
    # «применить», а не «включить»: многие твики как раз отключают функцию Windows
    if ($it.Appx) { $(if ($Done) { 'удалено' } else { 'удалить' }) }
    elseif ($it.Toggle.IsChecked) { $(if ($Done) { 'применено' } else { 'применить' }) }
    else { $(if ($Done) { 'возвращено как в Windows' } else { 'вернуть как в Windows' }) }
}

#region Reboot flag (cleared by an actual reboot)
function Get-BootTicks { "$((Get-CimInstance Win32_OperatingSystem).LastBootUpTime.Ticks)" }
function Set-RebootPending { Set-Content -Path $script:RebootFile -Value (Get-BootTicks); $script:RebootPending = $true; Update-RebootUi }
function Update-RebootUi {
    $v = $(if ($script:RebootPending) { 'Visible' } else { 'Collapsed' })
    $script:RebootBanner.Visibility = $v; $script:BtnReboot.Visibility = $v
}
function Invoke-Reboot {
    if ([Windows.MessageBox]::Show($script:Win, "Перезагрузить компьютер сейчас?`nСохраните открытые файлы.", 'OknoTune', 'YesNo', 'Question') -eq 'Yes') {
        try { Restart-Computer -ErrorAction Stop } catch { [void][Windows.MessageBox]::Show($script:Win, "Не удалось перезагрузить: $($_.Exception.Message)", 'OknoTune') }
    }
}
#endregion

#region Overlay dialog
function Show-Overlay([string]$title, [string]$sub) {
    $script:OvTitle.Text = $title; $script:OvSub.Text = $sub
    $script:OvBody.Children.Clear(); $script:OvLeft.Children.Clear(); $script:OvButtons.Children.Clear()
    $script:OvProgress.Visibility = 'Collapsed'; $script:OvProgress.Value = 0
    $script:Overlay.Visibility = 'Visible'
}
function Hide-Overlay { $script:Overlay.Visibility = 'Collapsed'; Show-View $script:CurView }
function Add-OvText([string]$text, [string]$color = '#C9CED6', [double]$size = 13, [string]$margin = '0,0,0,6', [switch]$Bold) {
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $text; $tb.Foreground = Brush $color; $tb.FontSize = $size; $tb.TextWrapping = 'Wrap'; $tb.Margin = $margin
    if ($Bold) { $tb.FontWeight = 'SemiBold' }
    [void]$script:OvBody.Children.Add($tb)
}
function Add-OvLine([string]$main, [string]$tail, [string]$dot) {
    # DockPanel, а не горизонтальный StackPanel: иначе длинный текст не переносится и обрезается
    $sp = New-Object Windows.Controls.DockPanel; $sp.Margin = '0,0,0,5'
    $e = New-Object Windows.Shapes.Ellipse; $e.Width = 7; $e.Height = 7; $e.Fill = Brush $dot; $e.Margin = '2,6,10,0'; $e.VerticalAlignment = 'Top'
    $tb = New-Object Windows.Controls.TextBlock; $tb.FontSize = 13; $tb.TextWrapping = 'Wrap'
    $r1 = New-Object Windows.Documents.Run $main; $r1.Foreground = Brush '#E6E8EB'
    $r2 = New-Object Windows.Documents.Run $tail; $r2.Foreground = Brush '#8B93A1'
    $tb.Inlines.Add($r1); $tb.Inlines.Add($r2)
    [void]$sp.Children.Add($e); [void]$sp.Children.Add($tb)
    [void]$script:OvBody.Children.Add($sp)
}
function Add-OvBox([string]$title, [string[]]$lines, [string]$bg, [string]$border, [string]$fg) {
    $b = New-Object Windows.Controls.Border
    $b.Background = Brush $bg; $b.BorderBrush = Brush $border; $b.BorderThickness = 1; $b.CornerRadius = 10; $b.Padding = '16,12'; $b.Margin = '0,10,0,6'
    $sp = New-Object Windows.Controls.StackPanel
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $title; $t.FontWeight = 'SemiBold'; $t.Foreground = Brush $fg; $t.FontSize = 13; $t.Margin = '0,0,0,6'
    [void]$sp.Children.Add($t)
    foreach ($l in $lines) {
        $x = New-Object Windows.Controls.TextBlock; $x.Text = "•  $l"; $x.Foreground = Brush $fg; $x.FontSize = 13; $x.TextWrapping = 'Wrap'; $x.Margin = '0,0,0,3'
        [void]$sp.Children.Add($x)
    }
    $b.Child = $sp; [void]$script:OvBody.Children.Add($b)
}
function Add-OvButton([string]$text, [scriptblock]$action, $param, [string]$style = 'Btn') {
    $b = New-Object Windows.Controls.Button
    $b.Content = $text; $b.Style = $script:Styles[$style]; $b.Margin = '8,0,0,0'; $b.Tag = @{ A = $action; P = $param }
    $b.Add_Click({ & $this.Tag.A $this.Tag.P })
    [void]$script:OvButtons.Children.Add($b)
}
#endregion
